import DonpaCore
import SwiftUI

#if os(iOS)
import UIKit
#endif

/// End-of-game result feedback: the manga result screen, score submission,
/// the restart pop, and haptics.
extension GameContent {

    /// Overlaid on the BOARD only, so the control strip stays live.
    ///
    /// Hit-testing gates on the LOGICAL state, outside the `if`, covering the
    /// outgoing fade: a click on the dismissing panel starts a recognizer on a
    /// dying view, and that stuck recognizer swallows every further click. With
    /// the gate, fade-time clicks fall through as the fresh game's first reveal.
    @ViewBuilder var mangaPanel: some View {
        ZStack {
            if let panel {
                MangaPanelView(
                    kind: panel,
                    hexCells: viewModel.config.isHex,
                    isDaily: panelIsDaily,
                    unlockedLabels: panelUnlocks,
                    earnedFeatTitles: panelFeats,
                    reduceMotion: reduceMotion,
                    guess: panelGuess,
                    pace: panelPace,
                    paceIsRecord: panelPaceIsRecord,
                    onContinue: { dismissPanel() }
                )
                .transition(.opacity)
            }
        }
        .allowsHitTesting(panel != nil)
        // The one-time Game Center ask; "Not now" is never asked again.
        .alert(
            Text("Report decorations to Game Center?", bundle: .module),
            isPresented: $showGCAsk
        ) {
            Button {
                gameCenter.setEnabled(true)
            } label: {
                Text("Enable", bundle: .module)
            }
            Button(role: .cancel) {
                gameCenter.prefs.markAsked()
            } label: {
                Text("Not now", bundle: .module)
            }
        } message: {
            Text(
                """
                Optional — decorations stay in the app either way. You can \
                change this later under Decorations in the Service Record.
                """, bundle: .module)
        }
    }

    /// Runs AFTER the submits so the derivable reconcile sees this game's
    /// records.
    private func recordFeats() {
        var fresh: [(id: AchievementID, tier: Int)] = []
        if let event = viewModel.lastEndEvent {
            fresh = AchievementEngine.momentary(event)
                .filter { achievements.record($0, at: event.date) }
                .map { (id: $0, tier: 1) }
        }
        fresh += achievements.reconcile(
            derivable: AchievementEngine.derivable(
                records: scoreboard.displayRecords,
                longestDailyStreak: dailyStore.longestStreak))
        panelFeats = fresh.map(\.id.title)
        guard !fresh.isEmpty else { return }
        // The FIRST decoration is the moment the Game Center question means
        // anything — arm the ask (it shows after the celebration dismisses).
        if !gameCenter.prefs.asked { pendingGCAsk = true }
        let titles = fresh.map(\.id.title).joined(separator: ", ")
        A11yAnnounce.post(
            String(localized: "Decoration earned: \(titles)", bundle: .module))
    }

    /// Gates only open on wins: diff the records around the submits, stamp the
    /// result panel's sticker, and tell VoiceOver (the sticker is transient).
    /// Silent under "Unlock all boards" — celebrating a gate the player can't
    /// perceive is noise (the diff resumes if they untoggle with gates closed).
    private func celebrateUnlocks(isWin: Bool, before: [String: ScoreRecord]) {
        panelUnlocks =
            isWin && !settings.unlockAll
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
        scene.soundPlayer?.play(result.isWin ? .win : .lose)

        // Snapshot BEFORE the submits, so a win can diff what it opened.
        let recordsBefore = scoreboard.displayRecords

        // submit() re-sets the highlight if THIS game was a record.
        scoreboard.clearRecentRecord()

        let kind: MangaPanelView.Kind
        let isWin = result.isWin
        panelIsDaily = navigator.activeDaily != nil
        switch result {
        case _ where navigator.activeDaily != nil:
            kind = recordDailyAttempt(result: result, daily: navigator.activeDaily!)
        case .won(let centiseconds, let config):
            kind = submitWin(centiseconds: centiseconds, config: config)
        case .lost:
            let progress = viewModel.game.progress
            // Prior best BEFORE submit overwrites it (nil = first run).
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
            panelPace = nil
            panelPaceIsRecord = false
        }
        // Outcome only — activity already accrued live via flushes. minesHit =
        // the single loss detonation; a win's disarmedMineCount reads the full set.
        scoreboard.recordGameOutcome(
            for: viewModel.config,
            won: isWin,
            minesHit: isWin ? 0 : 1,
            minesDisarmed: viewModel.game.board.disarmedMineCount,
            chordsUsed: viewModel.chordsThisGame)
        celebrateUnlocks(isWin: isWin, before: recordsBefore)
        recordFeats()
        showPanel(kind)

        // Discard the save NOW — the last debounced save would otherwise linger
        // as a stale Continue in New Game.
        autosave()

        if !reduceMotion {
            restartPop = true
            withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) { restartPop = false }
        }
    }

    private func submitWin(centiseconds: Int, config: GameConfig) -> MangaPanelView.Kind {
        // Prior bests BEFORE submit() overwrites them (nil = first-ever).
        let priorBest = scoreboard.best(for: config)
        let priorBestPace = scoreboard.displayRecords[config.storageKey]?.bestPace?.pace
        let threeBV = viewModel.lastEndEvent?.threeBV
        let isRecord = scoreboard.submit(
            centiseconds, for: config,
            noFlag: !viewModel.usedFlagEver, noChord: !viewModel.usedChordEver,
            threeBV: threeBV)
        panelPace = threeBV.map {
            RecentWin(date: Date(), centiseconds: centiseconds, threeBV: $0).pace
        }
        // "Best" only when it BEAT a prior pace — a first-ever log stays quiet
        // (every first win would otherwise shout).
        panelPaceIsRecord =
            panelPace.map { pace in priorBestPace.map { pace > $0 } ?? false } ?? false
        let totalWins = scoreboard.displayRecords.values.reduce(0) { $0 + $1.wins.total }
        if ReviewPrompt.shouldAsk(
            newBest: isRecord, totalWins: totalWins,
            promptedVersion: settings.reviewPromptedVersion,
            version: ReviewPrompt.currentVersion)
        {
            pendingReviewAsk = true
        }
        if isRecord {
            // Delta of the DISPLAYED (tenth-truncated) bests — a raw delta could
            // read "improved by 0.0s". nil = record stands but the shown value
            // didn't move, so no pill.
            let improvedBy = priorBest.flatMap {
                TimeFormat.displayedImprovement(from: $0, to: centiseconds)
            }
            return .record(centiseconds: centiseconds, improvedBy: improvedBy)
        }
        return .win
    }

    /// A short beat lets the board's detonation / win ripple land first.
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
        if pendingGCAsk {
            pendingGCAsk = false
            showGCAsk = true
        } else if pendingReviewAsk {
            pendingReviewAsk = false
            settings.reviewPromptedVersion = ReviewPrompt.currentVersion
            requestReview()
        }
    }

    private func fireHaptic(for result: GameResult) {
        #if os(iOS)
        guard settings.haptics else { return }  // the toggle means ALL haptics off
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(result.isWin ? .success : .error)
        #endif
    }
}

extension GameContent {
    /// The Service Record sheet, extracted to keep the body chain within the
    /// type-checker's budget. From the title (browsing) there's no current
    /// board → no "you are here" marker; in-game, mark the played config.
    var scoreboardSheet: some View {
        ScoreboardView(
            scoreboard: scoreboard, settings: settings, dailyStore: dailyStore,
            achievements: achievements, available: windowSize,
            gates: gates,
            currentConfig: navigator.showingTitle ? nil : viewModel.config,
            onPlay: { navigator.playConfigRequested = $0 },
            // "Manage rivals": swap to the Mess hall at root (deferred a tick —
            // the scoreboard is dismissing; two sheet swaps in one runloop race).
            // Hand the pause across FIRST, so the Record's dismiss doesn't
            // restart the clock during the swap.
            onMessHall: {
                if pausedForScores {
                    pausedForScores = false
                    pausedForMessHall = true
                }
                navigator.showingScores = false
                navigator.afterDismiss { navigator.showingMessHall = true }
            },
            friends: friends, gameCenter: gameCenter)
    }
}
