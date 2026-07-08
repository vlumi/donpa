import DonpaCore
import SwiftUI

#if os(iOS)
import UIKit
#endif

/// End-of-game result feedback: the manga result screen, score submission, the
/// restart-button pop, and haptics. Split from `GameView.swift` for the file/type
/// length caps.
extension GameContent {

    /// The end-of-game result screen, overlaid on the BOARD only so the control
    /// strip's actions stay live. Dims the board until dismissed (X / tap / Esc).
    ///
    /// Hit-testing is gated on the LOGICAL state (outside the `if`, so it applies
    /// to the outgoing fade too): the dismissing panel used to stay clickable
    /// through its 0.25s fade-out, and a rapid click landing there started a
    /// gesture recognition on a dying view — the hosting view's stuck recognizer
    /// then swallowed EVERY further click of the continuing rapid-click sequence
    /// (the board went dead until a ~1s pause let the chain expire). With the
    /// gate, a click during the fade passes straight through to the board, where
    /// it lands as the fresh game's first reveal.
    @ViewBuilder var mangaPanel: some View {
        ZStack {
            if let panel {
                MangaPanelView(
                    kind: panel,
                    hexCells: viewModel.config.isHex,
                    unlockedLabels: panelUnlocks,
                    reduceMotion: reduceMotion,
                    guess: panelGuess,
                    onContinue: { dismissPanel() }
                )
                .transition(.opacity)
            }
        }
        .allowsHitTesting(panel != nil)
    }

    /// The feats pass, AFTER the submits so the records include this game: the
    /// momentary gags off the end event, then the derivable reconcile picks up
    /// whatever this game's records now prove. Fresh earns announce to
    /// VoiceOver (the Decorations grid + earn sticker arrive with A4's UI).
    private func recordFeats() {
        var fresh: [(id: AchievementID, tier: Int)] = []
        if let event = viewModel.lastEndEvent {
            fresh = AchievementEngine.momentary(event)
                .filter { achievements.record($0, at: event.date) }
                .map { (id: $0, tier: 1) }
        }
        fresh += achievements.reconcile(
            derivable: AchievementEngine.derivable(records: scoreboard.displayRecords))
        guard !fresh.isEmpty else { return }
        let titles = fresh.map(\.id.title).joined(separator: ", ")
        A11yAnnounce.post(
            String(localized: "Decoration earned: \(titles)", bundle: .module))
    }

    /// Gates only open on wins: diff the records around the submits, stamp the
    /// result panel's sticker, and tell VoiceOver (the sticker is transient).
    private func celebrateUnlocks(isWin: Bool, before: [String: ScoreRecord]) {
        panelUnlocks =
            isWin
            ? UnlockGates.newlyUnlocked(
                before: before, after: scoreboard.displayRecords,
                winsBaseline: winsBaseline)
            : []
        if let spoken = MangaPanelView.unlockSpoken(panelUnlocks) {
            A11yAnnounce.post(spoken)
        }
    }

    /// The single end-of-game hook: haptic, score submission, the manga result
    /// screen, and a restart-button pop.
    func handleResult() {
        guard let result = viewModel.lastResult?.result else { return }
        fireHaptic(for: result)

        // Snapshot BEFORE the submits below, so a win can diff what it opened.
        let recordsBefore = scoreboard.displayRecords

        // Clear the prior record highlight; submit() below re-sets it if THIS game
        // was a record.
        scoreboard.clearRecentRecord()

        let kind: MangaPanelView.Kind
        let isWin = result.isWin
        switch result {
        case .won(let centiseconds, let config):
            // Capture the prior best BEFORE submit() overwrites it, so the panel can
            // show how much faster this clear was rather than the (already-on-timer)
            // final time. No prior best → a first-ever clear (improvedBy nil).
            let priorBest = scoreboard.best(for: config)
            let isRecord = scoreboard.submit(
                centiseconds, for: config,
                noFlag: !viewModel.usedFlagEver, noChord: !viewModel.usedChordEver)
            if isRecord {
                // The pill shows how much the DISPLAYED best changed (times truncate
                // to tenths) — a raw delta could read "improved by 0.0s" when both
                // times show the same tenth, or overstate by a tenth. nil (no pill)
                // when the visible value didn't move, even though the record stands.
                let improvedBy = priorBest.flatMap {
                    TimeFormat.displayedImprovement(from: $0, to: centiseconds)
                }
                kind = .record(centiseconds: centiseconds, improvedBy: improvedBy)
            } else {
                kind = .win
            }
        case .lost:
            // Record cleared % as a consolation score; the "new best %" pill shows
            // only when this loss beat the prior best, and by how much.
            let progress = viewModel.game.progress
            // Prior best progress BEFORE submit overwrites it (nil = first run).
            let priorProgress = scoreboard.bestProgress(for: viewModel.config)
            let isBest = scoreboard.submitLossProgress(progress, for: viewModel.config)
            let safeRemaining = viewModel.game.safeCellCount - viewModel.game.revealedSafeCount
            let best: MangaPanelView.LossBest
            if !isBest {
                best = .notBest
            } else if let prior = priorProgress {
                best = .improved(by: max(0, progress - prior))
            } else {
                best = .first
            }
            kind = .loss(progress: progress, safeRemaining: safeRemaining, best: best)
        }
        // The finished game's OUTCOME: games-played + the mine tally (activity
        // already accrued live via flushes). minesHit = the single loss detonation;
        // on a win disarmedMineCount reads the full set.
        scoreboard.recordGameOutcome(
            for: viewModel.config,
            won: isWin,
            minesHit: isWin ? 0 : 1,
            minesDisarmed: viewModel.game.board.disarmedMineCount,
            chordsUsed: viewModel.chordsThisGame)
        celebrateUnlocks(isWin: isWin, before: recordsBefore)
        recordFeats()
        showPanel(kind)

        // The game is over → discard its in-progress save now (a game is kept only
        // while playable). Without this the last debounced save lingered until the
        // next autosave, so New Game could still show a stale Continue for it.
        autosave()  // not in progress → clears this config's save

        if !reduceMotion {
            restartPop = true
            withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) { restartPop = false }
        }
    }

    /// Slam the result screen in after a short beat so the board's detonation / win
    /// ripple plays first. The beat is animation timing, not a hang.
    private func showPanel(_ kind: MangaPanelView.Kind) {
        InputTrace.log("panel scheduled")
        panelTask?.cancel()
        panelTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)  // let board FX land
            guard !Task.isCancelled else { return }
            InputTrace.log("panel shown")
            withAnimation(.easeOut(duration: 0.2)) { panel = kind }
        }
    }

    func dismissPanel() {
        InputTrace.log("panel dismissed (was \(panel == nil ? "nil" : "shown"))")
        panelTask?.cancel()
        withAnimation(.easeIn(duration: 0.25)) { panel = nil }
    }

    private func fireHaptic(for result: GameResult) {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(result.isWin ? .success : .error)
        #endif
    }
}
