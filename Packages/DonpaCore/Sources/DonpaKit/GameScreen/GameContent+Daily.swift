import DonpaCore
import SwiftUI

/// The daily challenge's pre-game review and result recording. The review
/// keeps the board VISIBLE but input-locked — study is explicitly free
/// (memorization is legitimate) — and Start performs the shared fixed
/// reveal, which is what starts the clock.
extension GameContent {
    @ViewBuilder var dailyReviewOverlay: some View {
        if navigator.dailyReviewActive, let daily = navigator.activeDaily {
            VStack(spacing: 14) {
                Spacer()
                VStack(spacing: 10) {
                    Text("Today's orders", bundle: .module)
                        .font(.title3.bold())
                    Text(verbatim: daily.config.fullLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(
                        "Same board for everyone — study freely; the clock starts on Start.",
                        bundle: .module
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    Button {
                        startDailyRun(daily)
                    } label: {
                        Text("Start", bundle: .module)
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isComputing)  // arming; the reveal would drop
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("daily.start")
                    Button {
                        navigator.dailyReviewActive = false
                        navigator.activeDaily = nil
                        goHome()
                    } label: {
                        Text("Cancel", bundle: .module)
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())  // swallow board taps while reviewing
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Daily challenge review", bundle: .module))
        }
    }

    func startDailyRun(_ daily: DailyChallenge.Board) {
        navigator.dailyReviewActive = false
        viewModel.reveal(daily.startCell)
    }

    /// A finished daily attempt: the day record is the celebration universe —
    /// config best times/pace logs are untouched (a memorized shared board is
    /// its own competition; normal counters still accrue via the outcome and
    /// activity paths).
    func recordDailyAttempt(
        result: GameResult, daily: DailyChallenge.Board
    ) -> MangaPanelView.Kind {
        let prior = dailyStore.displayRecords[daily.dateKey]
        switch result {
        case .won(let centiseconds, _):
            let threeBV = viewModel.lastEndEvent?.threeBV
            dailyStore.recordAttempt(
                dateKey: daily.dateKey,
                .init(
                    won: true, centiseconds: centiseconds, threeBV: threeBV, progress: 1,
                    live: daily.dateKey == DailyChallenge.dateKey()))
            panelPace = threeBV.map {
                RecentWin(date: Date(), centiseconds: centiseconds, threeBV: $0).pace
            }
            let priorBest = prior?.best
            panelPaceIsRecord =
                panelPace.map { pace in priorBest.map { pace > $0.pace } ?? false } ?? false
            if centiseconds < (priorBest?.centiseconds ?? .max) {
                let improvedBy = priorBest.flatMap {
                    TimeFormat.displayedImprovement(from: $0.centiseconds, to: centiseconds)
                }
                return .record(centiseconds: centiseconds, improvedBy: improvedBy)
            }
            return .win
        case .lost:
            let progress = viewModel.game.progress
            dailyStore.recordAttempt(
                dateKey: daily.dateKey,
                .init(
                    won: false, centiseconds: 0, threeBV: nil, progress: progress,
                    live: daily.dateKey == DailyChallenge.dateKey()))
            let priorProgress = prior?.bestProgress
            let safeRemaining = viewModel.game.safeCellCount - viewModel.game.revealedSafeCount
            let best: MangaPanelView.LossBest
            if prior?.cleared == true || progress <= (priorProgress ?? 0) {
                best = .notBest
            } else if let priorProgress {
                best = .improved(by: max(0, progress - priorProgress))
            } else {
                best = .first
            }
            panelPace = nil
            panelPaceIsRecord = false
            return .loss(progress: progress, safeRemaining: safeRemaining, best: best)
        }
    }
}
