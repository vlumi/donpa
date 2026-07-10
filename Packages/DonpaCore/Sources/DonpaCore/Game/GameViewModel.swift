import Combine
import Foundation

/// The live game clock, split out as its own observable so the ~10×/sec timer tick
/// only re-renders the timer readout — NOT the whole `GameContent` body. (Reading
/// the tick straight off `GameViewModel` made every view observing the VM re-render
/// 10×/sec — wasteful, and a battery drain on iOS in particular.)
@MainActor
public final class GameClock: ObservableObject {
    /// Elapsed centiseconds, from the wall clock (not a tick count) so it's exact.
    /// Setter internal (was fileprivate): the writers live in
    /// GameViewModel+Timer.swift, split out for the file-length budget.
    @Published public internal(set) var elapsedCentiseconds: Int = 0
}

/// Bridges the pure `Game` value type to SwiftUI/SpriteKit: owns the current
/// game/config/timer and republishes on board change so views + scene redraw.
@MainActor
public final class GameViewModel: ObservableObject {
    @Published public private(set) var game: Game
    @Published public private(set) var config: GameConfig
    /// The live clock, observed on its own by the timer readout (see `GameClock`).
    public let clock = GameClock()
    /// Elapsed centiseconds — the live display value lives on `clock`; this mirrors
    /// it for snapshot/restore/tests without making the VM re-publish on every tick.
    public var elapsedCentiseconds: Int { clock.elapsedCentiseconds }

    /// Bumped on every state change so the scene re-renders without diffing.
    @Published public private(set) var revision: Int = 0

    /// Bumped only on a fresh game, so the scene resets its camera then (not on
    /// every reveal).
    @Published public private(set) var gameID: Int = 0

    /// The win's final time + config, set at win, cleared on next new game.
    @Published public private(set) var lastWin: (config: GameConfig, centiseconds: Int)?

    /// Most recent outcome for end-of-game feedback; cleared on next new game.
    @Published public private(set) var lastResult: GameResultEvent?
    private var resultCounter = 0

    @Published public var inputMode: InputMode = .reveal

    // Timer state — internal (not `private`, which is file-scoped): the timer
    // methods live in GameViewModel+Timer.swift for the file-length budget.
    var timer: AnyCancellable?
    /// Segmented clock: `elapsed = accumulated + (now − runningSince)`. Pausing
    /// folds the live span into `accumulated` (a plain number, persists cleanly).
    var accumulatedCentiseconds = 0
    var runningSince: Date?

    /// Clock paused mid-game (game live, clock stopped) — drives the pause overlay.
    /// Setter internal for GameViewModel+Timer.swift (see the timer state above).
    @Published public internal(set) var isPaused = false

    /// True while a reveal/chord computes OFF the main thread (heavy flood-fill /
    /// placement on a huge board). Blocks board input so a tap can't land on a
    /// board that hasn't finished updating (could be a guaranteed mine).
    @Published public private(set) var isComputing = false

    /// Flag *placements* this game (each hidden→flagged action, so a re-flag counts
    /// again — the lifetime stat counts actions). Reset on new game / restore.
    public private(set) var flagsPlacedThisGame = 0

    /// Chord actions this game (a mastery signal; folded into the game-end stats).
    /// Reset on new game / restore.
    public private(set) var chordsThisGame = 0

    /// Reveal-type actions this game (reveals of a hidden cell + real chords) —
    /// the achievement layer's "which action was fatal" clock. POISONED on
    /// restore (a huge count): the pre-save actions are unknowable, so a
    /// momentary feat like "lose on your second reveal" must never fire on a
    /// resumed game (deny over false-award, like the purity bits).
    public private(set) var revealActionsThisGame = 0
    /// The restore poison — far above any real per-game action count.
    static let restoredActionsPoison = 1 << 20

    /// A finished game's momentary facts, for the achievement layer. Fired once
    /// per game end, after the final activity flush.
    public var onGameEnd: ((GameEndEvent) -> Void)?
    /// The same event, kept for hosts that react to `lastResult` (whose handler
    /// runs AFTER the score submits — the right moment to evaluate feats).
    public private(set) var lastEndEvent: GameEndEvent?

    /// Sticky "purity" bits for no-flag / no-chord feats: latch true the moment the
    /// feat is broken and never reset within a game. On RESTORE they default to
    /// "violated" (true) — a resumed game can't earn these (board state can't prove a
    /// clean run), erring toward denial over a false award. See the achievements plan.
    public private(set) var usedFlagEver = false
    public private(set) var usedChordEver = false

    /// Activity already flushed for THIS game, so a flush only sends the new delta.
    /// Internal (not private): the flush logic lives in GameViewModel+Activity.swift,
    /// split out for the file-length budget.
    var flushedTiles = 0
    var flushedFlags = 0
    var flushedCentiseconds = 0

    /// Pushes the unflushed activity DELTA (tiles/flags/time) to the lifetime
    /// totals — called on pause (also when the scoreboard opens), background, and
    /// game end/discard, so it accrues without a per-tile write storm and an
    /// abandoned game still counts. Set by the host (which owns the scoreboard);
    /// Core never references it.
    public var onActivityFlush:
        ((_ tilesDelta: Int, _ flagsDelta: Int, _ centisecondsDelta: Int) -> Void)?

    /// An open finished, uncovering `openedCells` non-mine cells — fires only when
    /// that's > 0 (a mine hit or no-op stays silent), AFTER the off-main compute
    /// settles. `flooded` is true when a 0-cell cascade ran (hitting a 0 opens a
    /// whole region for free) — the "area opened" the sound flags, vs the count the
    /// haptic scales by. Set by the host (a UI feedback concern); Core never uses it.
    public var onReveal: ((_ openedCells: Int, _ flooded: Bool) -> Void)?

    /// A reveal was a FORCED guess (no certainly-safe cell existed — see
    /// `GuessOdds`): reports its survival odds and whether the player survived it.
    /// Carries the config the guess was made on, since the analysis is async and
    /// the player may have moved to another board by the time it lands. Set by the
    /// host (which owns the scoreboard); Core never references it.
    public var onForcedGuess:
        ((_ config: GameConfig, _ survival: Double, _ survived: Bool) -> Void)?

    /// The verdict on the LATEST analyzed action, for in-the-moment UI feedback
    /// (the toast / result-panel pill). Cleared on every new reveal/chord and on
    /// new game/restore, so a non-nil value always describes the most recent
    /// action — on a finished game, the one that ended it. Setter internal for
    /// GameViewModel+Guess.swift (Swift private is file-scoped).
    @Published public internal(set) var lastForcedGuess: ForcedGuessEvent?
    /// Monotonic id for `lastForcedGuess` events (see `ForcedGuessEvent.id`).
    var guessEventCounter = 0

    /// Whether the board extends beyond the viewport; published by `BoardScene`
    /// each frame so the chrome can enable/disable the minimap toggle.
    @Published public var boardExceedsViewport = false

    /// Live camera view, kept current by `BoardScene` so `snapshot()` can persist
    /// it. Plain (not `@Published`) — written every frame, nothing observes it.
    public var cameraView: CameraView?

    /// One-shot camera view to restore on the next game, consumed by `BoardScene`.
    /// Separate from `cameraView` (which the scene overwrites each frame) so it
    /// survives until applied.
    public var pendingCameraRestore: CameraView?

    public init(config: GameConfig = .beginner) {
        self.config = config
        self.game = Game(config: config)
    }

    /// True while the board is only an unplayed launch placeholder (the initial
    /// board, or the `prime(config:)` swap to the persisted config): its config's
    /// on-disk save is still the player's real game, so autosave must not read the
    /// untouched `.notStarted` board as "no game → discard the save". See `prime`.
    public internal(set) var isPrimedBoard = true

    public var status: GameStatus { game.status }
    public var flagsRemaining: Int { game.flagsRemaining }
    public var boardWidth: Int { config.width }
    public var boardHeight: Int { config.height }

    // MARK: Actions

    /// Input accepted only when not paused and not mid-compute (the compute gate
    /// stops a tap landing on a board the in-flight reveal is about to change).
    private var canTakeInput: Bool { !isPaused && !isComputing }

    /// Whether revealing `c` would detonate a mine right now — the scene fires the
    /// explosion instantly on tap (before the off-thread reveal). False on the
    /// opening move, since mines exist only after the always-safe first click.
    public func canRevealHitMine(_ c: Coord) -> Bool {
        guard canTakeInput, game.status == .playing else { return false }
        return game.board[c].state == .hidden && game.board[c].isMine
    }

    /// In-flight compute, held so tests can await it. Not for production callers.
    private var pendingWork: Task<Void, Never>?

    /// The `gameID` the most recently started compute belongs to. Lets a stale
    /// task tell whether a newer compute is arming the current generation (so it
    /// leaves the gate alone) or not (so it must release `isComputing` itself).
    private var computeGeneration = -1

    /// Await the current reveal/chord compute (test-only).
    public func awaitPendingWork() async {
        await pendingWork?.value
    }

    /// Run a heavy board mutation off the main thread on a COW copy, apply it back
    /// on the main actor, then `afterApply` + redraw. `canTakeInput` gates to one
    /// compute at a time.
    private func computeOffMain(
        _ mutate: @Sendable @escaping (inout Game) -> Void,
        afterApply: (() -> Void)? = nil
    ) {
        isComputing = true
        InputTrace.log("gate ON gid=\(gameID)")
        let snapshot = game  // O(1) COW; the task's mutation triggers the copy
        let tokenBefore = game.changeToken
        let generation = gameID
        computeGeneration = generation
        pendingWork = Task {
            let updated = await Task.detached {
                var working = snapshot
                mutate(&working)
                return working
            }.value
            let outcome = Self.computeOutcome(
                finished: generation, current: self.gameID,
                latestStarted: self.computeGeneration)
            InputTrace.log(
                "gate \(outcome.releaseGate ? "OFF" : "held") fin=\(generation) "
                    + "cur=\(self.gameID) apply=\(outcome.applyResult)")
            if outcome.applyResult {
                self.game = updated
                // Skip the redraw/autosave/minimap-rebuild if nothing actually changed
                // — e.g. chording a number whose flag count doesn't match does no work,
                // and on a huge board a stream of such no-op taps would otherwise each
                // queue a full-board snapshot + minimap raster and back up the app.
                if updated.changeToken != tokenBefore {
                    afterApply?()
                    self.bump()
                }
            }
            if outcome.releaseGate { self.isComputing = false }
        }
    }

    public func reveal(_ c: Coord) {
        InputTrace.log(
            "reveal \(c) computing=\(isComputing) paused=\(isPaused) status=\(game.status)")
        guard canTakeInput, game.status == .notStarted || game.status == .playing else { return }
        let wasNotStarted = game.status == .notStarted
        // Count only reveals that can DO something (a tap on a revealed cell is
        // routed to chord by the UI; off-board taps no-op) — the action clock
        // must not tick on strays.
        if game.board[c].state == .hidden { revealActionsThisGame += 1 }
        lastForcedGuess = nil  // the feedback event tracks the LATEST action
        // Capture the PRE-reveal state for the guess analysis (O(1) COW copy) —
        // only when analysis is even possible, so the huge boards never retain a
        // second board copy.
        let pre = preGuessState()
        let safeBefore = game.revealedSafeCount
        computeOffMain({ game in game.reveal(c) }) { [weak self] in
            guard let self else { return }
            // The first reveal places mines and starts the clock.
            if wasNotStarted, self.game.status == .playing { self.startTimer() }
            let opened = self.game.revealedSafeCount - safeBefore
            if opened > 0 {
                // A single reveal floods iff the clicked cell was a 0 (which opens
                // its whole region); a numbered cell opens just itself.
                let flooded =
                    self.game.status != .lost && self.game.board[c].adjacentMines == 0
                self.onReveal?(opened, flooded)
            }
            self.finishIfEnded()
            // A single reveal only ever loses on the clicked cell, so
            // post-state loss ⟺ died to it.
            if let pre {
                self.reportGuess(survived: self.game.status != .lost) {
                    GuessOdds.analyze(pre, clicked: c)
                }
            }
        }
    }

    /// Cycle a cell's mark. `useQuestionMarks` (from Settings) turns the flag into
    /// a flag → "?" → clear cycle; off, it's the plain flag toggle.
    public func toggleFlag(_ c: Coord, useQuestionMarks: Bool = false) {
        InputTrace.log(
            "flag \(c) computing=\(isComputing) paused=\(isPaused) status=\(game.status)")
        // O(1), so synchronous — but still gated mid-compute / paused / finished.
        guard canTakeInput, game.status == .notStarted || game.status == .playing else { return }
        let before = game.board[c].state
        game.toggleFlag(c, useQuestionMarks: useQuestionMarks)
        let after = game.board[c].state
        // A tap on a revealed cell (or off-board) changes nothing — skip the bump
        // too, or every stray right-click schedules a full-board autosave + redraw.
        guard after != before else { return }
        if after == .flagged {
            flagsPlacedThisGame += 1
        }
        // A "?" is external memory too: placing either mark violates Bare Hands.
        // The latch stays set even after cycling back to hidden.
        if after == .flagged || after == .questioned {
            usedFlagEver = true
        }
        bump()
    }

    public func chord(_ c: Coord) {
        InputTrace.log(
            "chord \(c) computing=\(isComputing) paused=\(isPaused) status=\(game.status)")
        // Gated on .playing so a post-game chord can't re-publish the result (which
        // would replay the end-game panel on every click).
        guard canTakeInput, game.status == .playing else { return }
        // The UI routes EVERY tap on a revealed cell here (including 0-cells), so
        // only count a chord that will actually reveal something — a stray tap must
        // not inflate chordsUsed or burn the no-chord feat. Skipping the compute for
        // no-ops is a bonus.
        guard game.canChord(c) else { return }
        chordsThisGame += 1
        revealActionsThisGame += 1
        usedChordEver = true
        lastForcedGuess = nil  // the feedback event tracks the LATEST action
        // A chord is analyzed as a guess too (the SET of cells it opens at once):
        // a throwaway flag placed just to avoid switching input modes makes the
        // chord itself the guess being executed. Provably-safe chords report
        // nothing, exactly like certain single reveals.
        let pre = preGuessState()
        let safeBefore = game.revealedSafeCount
        // The neighbours this chord will open — used after to tell a plain
        // multi-open (all numbered) from a flood (one of them was a 0 that
        // cascaded), matching "flood = hit a 0".
        let opening = game.board.topology.neighbors(of: c).filter {
            game.board[$0].state == .hidden || game.board[$0].state == .questioned
        }
        computeOffMain({ game in game.chord(c) }) { [weak self] in
            guard let self else { return }
            // A chord opens cells too — feed the same onReveal so its open sound
            // (tick vs the fuller flood) matches a single reveal.
            let opened = self.game.revealedSafeCount - safeBefore
            if opened > 0 {
                // Flood iff one of the cells the chord opened was a 0.
                let flooded =
                    self.game.status != .lost
                    && opening.contains { self.game.board[$0].adjacentMines == 0 }
                self.onReveal?(opened, flooded)
            }
            self.finishIfEnded()
            if let pre {
                self.reportGuess(survived: self.game.status != .lost) {
                    GuessOdds.analyzeChord(pre, at: c)
                }
            }
        }
    }

    public func newGame(config: GameConfig? = nil, seed: UInt64? = nil) {
        // Flush the outgoing game's activity before discarding it, so abandoning a
        // dug-into game still counts. (A finished game already flushed at end.)
        if game.status == .playing { flushActivity() }
        if let config { self.config = config }
        game = Game(config: self.config)
        clock.elapsedCentiseconds = 0
        lastWin = nil
        lastResult = nil
        lastForcedGuess = nil
        inputMode = .reveal
        pendingCameraRestore = nil
        cameraView = nil
        isComputing = false  // gameID bumps below → any in-flight compute is dropped
        flagsPlacedThisGame = 0
        chordsThisGame = 0
        revealActionsThisGame = 0
        usedFlagEver = false
        usedChordEver = false
        flushedTiles = 0
        flushedFlags = 0
        flushedCentiseconds = 0
        resetTimer()
        isPrimedBoard = false  // player-requested (prime() re-flags the launch swap)
        gameID &+= 1
        InputTrace.log("newGame gid=\(gameID)")
        bump()
        armBoard(seed: seed)
    }

    /// Pre-place mines off the main thread right after a new game, so the heavy
    /// placement on a huge board happens while the player looks at the fresh board,
    /// not on their first tap (the first reveal then only relocates mines under the
    /// click). The empty board shows immediately, gated by `isComputing` while arming.
    /// `seed` (perf harness only) makes mine placement deterministic so a profiled
    /// board is identical run to run; nil uses the system generator (normal play).
    private func armBoard(seed: UInt64? = nil) {
        computeOffMain({ game in
            if let seed {
                var rng = SeededGenerator(seed: seed)
                game.placeMinesEagerly(using: &rng)
            } else {
                var rng = SystemRandomNumberGenerator()
                game.placeMinesEagerly(using: &rng)
            }
        })
    }

    /// Restore a persisted game and resume its clock from the saved elapsed.
    public func restore(from snapshot: GameSnapshot) {
        config = snapshot.config
        game = snapshot.makeGame()
        lastWin = nil
        lastResult = nil
        lastForcedGuess = nil
        inputMode = snapshot.inputMode
        pendingCameraRestore = snapshot.camera
        cameraView = snapshot.camera
        timer?.cancel()
        accumulatedCentiseconds = snapshot.elapsedCentiseconds
        clock.elapsedCentiseconds = snapshot.elapsedCentiseconds
        isPaused = false
        isComputing = false
        // Flag placements aren't persisted, so a resumed game only counts ones made
        // after resume (a minor under-count, not worth a snapshot field).
        flagsPlacedThisGame = 0
        chordsThisGame = 0
        revealActionsThisGame = Self.restoredActionsPoison
        // Purity bits default to VIOLATED on restore: board state can't prove a clean
        // no-flag/no-chord run, so a resumed game can't earn those feats (deny over
        // false-award). A non-empty restored flag set makes usedFlag definitely true;
        // chord leaves no trace, so it's unknowable → true. See the achievements plan.
        usedFlagEver = true
        usedChordEver = true
        // Seed flush trackers to the restored state: pre-save tiles/time were
        // already flushed, so only post-resume activity counts (no re-adding).
        flushedTiles = game.revealedSafeCount
        flushedFlags = 0
        flushedCentiseconds = snapshot.elapsedCentiseconds
        if game.status == .playing { startTimer() } else { runningSince = nil }
        isPrimedBoard = false  // a restored game is the player's, not the placeholder
        gameID &+= 1
        bump()
    }

    /// Stop the clock, capture a win, and publish the outcome.
    private func finishIfEnded() {
        guard game.status == .won || game.status == .lost else { return }
        let finalCentiseconds = currentCentiseconds()
        timer?.cancel()
        timer = nil
        runningSince = nil
        accumulatedCentiseconds = finalCentiseconds
        clock.elapsedCentiseconds = finalCentiseconds
        // Flush the final activity slice BEFORE the host records the outcome, so the
        // end record adds only games-played + win/loss + mines, not tiles/flags/time
        // again (those flow through flushes).
        flushActivity()
        let result: GameResult
        if game.status == .won {
            lastWin = (config: config, centiseconds: finalCentiseconds)
            result = .won(centiseconds: finalCentiseconds, config: config)
        } else {
            result = .lost(at: game.lossCoord)
        }
        resultCounter += 1
        lastResult = GameResultEvent(id: resultCounter, result: result)
        let endEvent = event(finalCentiseconds: finalCentiseconds)
        lastEndEvent = endEvent
        onGameEnd?(endEvent)
    }

    private func bump() { revision &+= 1 }
}
