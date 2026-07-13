/// The overall play state.
public enum GameStatus: String, Sendable, Equatable, Codable {
    case notStarted
    case playing
    case won
    case lost

    /// Still accepting play (not yet won or lost).
    public var isLive: Bool { self == .notStarted || self == .playing }
    /// Decided, one way or the other.
    public var isFinished: Bool { self == .won || self == .lost }
    public var isPlaying: Bool { self == .playing }
}

/// Drives the rules: first-click mine placement, flood-fill reveal, flagging,
/// chording, and win/lose detection. Geometry-agnostic — all neighbour
/// questions go through `Topology` (via `Board`).
public struct Game: Sendable {
    public private(set) var board: Board
    public private(set) var status: GameStatus = .notStarted
    public let mineCount: Int

    /// Non-mine cells revealed, tracked incrementally so win detection is O(1).
    /// A win is exactly `revealedSafeCount == safeCellCount`.
    public private(set) var revealedSafeCount: Int = 0

    public var safeCellCount: Int { board.cellCount - mineCount }

    /// A cheap (O(1)) fingerprint of player-visible state, so a no-op reveal/chord
    /// (e.g. chording a number whose flags don't match) can be detected and skip the
    /// expensive redraw/autosave/minimap-rebuild. Covers every mutation: a reveal
    /// raises `revealedSafeCount` or ends the game; a flag changes `flagCount`; a
    /// loss/win changes `status`. Compare before/after a mutation.
    public var changeToken: Int {
        var h = Hasher()
        h.combine(revealedSafeCount)
        h.combine(board.flagCount)
        h.combine(status)
        return h.finalize()
    }

    /// Fraction of safe cells revealed, 0...1; 1.0 is a win.
    public var progress: Double {
        let safe = safeCellCount
        return safe > 0 ? Double(revealedSafeCount) / Double(safe) : 0
    }

    /// The cell whose reveal detonated on a loss (even via a chord); nil unless lost.
    public private(set) var lossCoord: Coord?

    private let topology: any RectangularTopology
    private var minesPlaced = false

    /// How the first click arms the board: standard random placement, or The
    /// Range's verified no-guess generation (up to ~1 s on XL — it runs inside
    /// the same off-main compute as any first reveal, behind the processing
    /// overlay). Falls back to a standard layout if the generator gives up
    /// (astronomically rare at practice density).
    public enum MinePlacement: Sendable { case standard, noGuess }
    public private(set) var placement: MinePlacement = .standard

    public init(difficulty: Difficulty) {
        let topology = BoundedSquareTopology(width: difficulty.width, height: difficulty.height)
        self.topology = topology
        self.board = Board(topology: topology)
        self.mineCount = difficulty.mineCount
    }

    /// Start a game from a `GameConfig` (supplies topology, mine count, and —
    /// for Drills — the no-guess placement strategy).
    public init(config: GameConfig) {
        self.topology = config.topology
        self.board = Board(topology: config.topology)
        self.mineCount = config.mineCount
        self.placement = config.family == .practice ? .noGuess : .standard
    }

    /// Inject any topology directly (variants / tests).
    public init(topology: any RectangularTopology, mineCount: Int) {
        self.topology = topology
        self.board = Board(topology: topology)
        self.mineCount = mineCount
    }

    /// Test seam: start with a known mine layout already placed, as if the first
    /// click had happened — for deterministic boards.
    init(topology: any RectangularTopology, mines: Set<Coord>) {
        self.topology = topology
        var board = Board(topology: topology)
        board.placeMines(at: mines)
        self.board = board
        self.mineCount = mines.count
        self.minesPlaced = true
        self.status = .playing
    }

    /// Rebuild a game from a persisted snapshot. Mines are restored exactly (not
    /// re-randomized — they're first-click-safe).
    public static func restored(from s: GameSnapshot) -> Game {
        // Trust the SAVED layout's count over the config's freshly-computed one:
        // the config is symbolic, so a density retune between builds would
        // otherwise skew safeCellCount/flagsRemaining against the actual mines
        // (early win, or a board that can never be won).
        let mineCount = s.mines.isEmpty ? s.config.mineCount : s.mines.count
        var game = Game(topology: s.config.topology, mineCount: mineCount)
        game.board.restore(
            mines: s.mines, revealed: s.revealed, flagged: s.flagged, questioned: s.questioned)
        game.minesPlaced = !game.board.mineCoords.isEmpty
        game.status = s.status
        // Derive from the restored board, not the saved number, so a tampered
        // save can't skew progress or win detection.
        game.revealedSafeCount = game.board.revealedSafeCount
        game.lossCoord = s.lossCoord
        return game
    }

    public var flagsRemaining: Int { mineCount - board.flagCount }

    // MARK: - Reveal

    /// Reveals `c`. On the first reveal, mines are placed avoiding `c` and its
    /// neighbours, guaranteeing a 0-opening.
    public mutating func reveal(_ c: Coord) {
        var rng = SystemRandomNumberGenerator()
        reveal(c, using: &rng)
    }

    /// Generator seam (see `PracticeBoard`): relocate one mine mid-deduction.
    mutating func moveMineForGeneration(from old: Coord, to new: Coord) {
        board.moveMine(from: old, to: new)
    }

    /// The `.noGuess` first-click layout: a verified no-guess board, or a plain
    /// safe-zone layout when the generator gives up (astronomically rare at The
    /// Range's density — internal so the fallback stays testable).
    static func noGuessMines<R: RandomNumberGenerator>(
        topology: any RectangularTopology, mineCount: Int, firstClick: Coord, using rng: inout R
    ) -> Set<Coord> {
        PracticeBoard.mines(
            topology: topology, mineCount: mineCount, firstClick: firstClick, using: &rng)
            ?? MinePlacer.placeMines(
                topology: topology, mineCount: mineCount, firstClick: firstClick, using: &rng)
    }

    /// Arm the board off-thread before the first click is known: place all mines
    /// with NO safe zone; the first reveal relocates any under it. Only acts on a
    /// fresh board — and never on a no-guess board, whose layout can only be
    /// generated once the first click is known.
    public mutating func placeMinesEagerly<R: RandomNumberGenerator>(using rng: inout R) {
        guard !minesPlaced, placement == .standard else { return }
        let mines = MinePlacer.randomMines(topology: topology, mineCount: mineCount, using: &rng)
        board.placeMines(at: mines)
        minesPlaced = true
    }

    public mutating func reveal<R: RandomNumberGenerator>(_ c: Coord, using rng: inout R) {
        guard status.isLive else { return }
        // Shadow with the FOLDED coord: on a wrapped topology normalize never fails,
        // and using the raw coord past this point would read/write phantom off-board
        // cells (silent no-op writes, and a first-click safe zone around the wrong
        // cell). Bounded topologies still reject off-board here.
        guard let c = topology.normalize(c) else { return }
        // A "?" cell is diggable — the player marked a maybe, then decided to open
        // it (directly or via a chord). A flag still protects; only hidden/"?" open.
        guard board[c].state == .hidden || board[c].state == .questioned else { return }

        if !minesPlaced {
            // Not pre-armed: place now, excluding the first-click safe zone.
            // Drills generates a verified no-guess layout instead (with a
            // plain layout as the give-up fallback — see MinePlacement).
            let mines: Set<Coord>
            switch placement {
            case .standard:
                mines = MinePlacer.placeMines(
                    topology: topology, mineCount: mineCount, firstClick: c, using: &rng)
            case .noGuess:
                mines = Self.noGuessMines(
                    topology: topology, mineCount: mineCount, firstClick: c, using: &rng)
            }
            board.placeMines(at: mines)
            minesPlaced = true
            status = .playing
        } else if status == .notStarted {
            // Pre-armed without a safe zone; move any mines out of the click's
            // neighbourhood so it opens a region.
            var safeZone: Set<Coord> = [c]
            safeZone.formUnion(topology.neighbors(of: c))
            board.relocateMines(outOf: safeZone, using: &rng)
            status = .playing
        }

        if board[c].isMine {
            board[c].state = .revealed
            status = .lost
            lossCoord = c
            revealAllMines()
            return
        }

        floodFill(from: c)
        checkWin()
    }

    /// Reveals a 0-region: iterative flood fill (stack-based — `popLast`) that
    /// expands only out of 0-cells, so numbered cells form the border. Flagged
    /// and mine cells are never enqueued; a "?" is swept like a hidden cell (it
    /// marks a maybe, and only a flag blocks the cascade).
    private mutating func floodFill(from start: Coord) {
        var queue = [start]
        var enqueued: Set<Coord> = [start]

        while let c = queue.popLast() {
            board[c].state = .revealed
            revealedSafeCount += 1  // flood-fill only ever reveals non-mine cells
            guard board[c].adjacentMines == 0 else { continue }
            for n in topology.neighbors(of: c) where !enqueued.contains(n) {
                let s = board[n].state
                guard s == .hidden || s == .questioned, !board[n].isMine else { continue }
                enqueued.insert(n)
                queue.append(n)
            }
        }
    }

    // MARK: - Flagging

    /// Advance a cell's mark. With `useQuestionMarks` the cycle is
    /// hidden → flagged → "?" → hidden (the classic third state); without it, the
    /// plain hidden ↔ flagged toggle. A "?" is a note, not a claim — it never
    /// counts as a flag anywhere (counter, chord, over-flag).
    public mutating func toggleFlag(_ c: Coord, useQuestionMarks: Bool = false) {
        guard status.isLive else { return }
        // Folded coord, same as `reveal`: a raw wrapped coord would pass the check
        // but write to a phantom cell.
        guard let c = topology.normalize(c) else { return }
        switch board[c].state {
        case .hidden: board[c].state = .flagged
        case .flagged: board[c].state = useQuestionMarks ? .questioned : .hidden
        case .questioned: board[c].state = .hidden
        case .revealed: break
        }
    }

    // MARK: - Chord

    /// If `c` is a revealed number whose adjacent flag count equals its number,
    /// reveal all its non-flagged neighbours. Mis-flagging can lose the game.
    public mutating func chord(_ c: Coord) {
        var rng = SystemRandomNumberGenerator()
        chord(c, using: &rng)
    }

    public mutating func chord<R: RandomNumberGenerator>(_ c: Coord, using rng: inout R) {
        guard status == .playing else { return }
        guard board[c].state == .revealed, board[c].adjacentMines > 0 else { return }
        let neighbors = topology.neighbors(of: c)
        let flagged = neighbors.filter { board[$0].state == .flagged }.count
        guard flagged == board[c].adjacentMines else { return }
        // A "?" is not a flag: it doesn't protect the cell, so a chord opens it just
        // like a hidden one (and can lose the game on it — that's the gamble).
        for n in neighbors where board[n].state == .hidden || board[n].state == .questioned {
            reveal(n, using: &rng)
            if status == .lost { return }
        }
    }

    /// Whether a chord on `c` would actually reveal something: a revealed number
    /// whose adjacent flag count matches, with at least one hidden neighbour left.
    /// The UI routes EVERY tap on a revealed cell through `chord`, so callers use
    /// this to skip the compute — and any chord *stats* — for no-op taps (a stray
    /// tap on a 0-cell must not count as "used chord").
    public func canChord(_ c: Coord) -> Bool {
        guard status == .playing else { return false }
        guard board[c].state == .revealed, board[c].adjacentMines > 0 else { return false }
        let neighbors = topology.neighbors(of: c)
        guard neighbors.contains(where: { board[$0].state == .hidden }) else { return false }
        return neighbors.filter { board[$0].state == .flagged }.count == board[c].adjacentMines
    }

    // MARK: - Win/lose helpers

    private mutating func checkWin() {
        guard revealedSafeCount == safeCellCount else { return }
        status = .won
        flagAllMines()
    }

    private mutating func revealAllMines() {
        for c in board.mineCoords where board[c].state != .flagged {
            // Leave correctly-flagged mines flagged: revealing them would clear the
            // flag and make `flagsRemaining` jump back up after a loss.
            board[c].state = .revealed
        }
    }

    private mutating func flagAllMines() {
        for c in board.mineCoords {
            board[c].state = .flagged
        }
    }
}
