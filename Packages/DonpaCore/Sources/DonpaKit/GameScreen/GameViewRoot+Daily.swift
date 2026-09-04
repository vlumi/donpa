import DonpaCore
import SwiftUI

/// The daily-challenge entry points: today's board, resuming an in-progress
/// save (a save is sacred — opening always continues it), and the in-progress
/// marker set the Home card and calendar read.
extension GameView {
    var todaysBoard: DailyChallenge.Board? {
        DailyChallenge.board(for: DailyChallenge.dateKey())
    }

    /// Recompute which days have an unfinished daily save, from the daily store's
    /// sidecar summaries (each carries its `dateKey`). Cheap — daily boards are
    /// small.
    func refreshDailySaveDates() {
        dailySaveDates = Set(dailySaveStore.summaries().compactMap(\.dateKey))
    }

    /// Start (or re-enter) today's board. An unfinished save for today resumes
    /// straight into it; otherwise a fresh attempt (review overlay arms via the
    /// gameID change in GameContent).
    func startDaily() {
        guard let board = todaysBoard else { return }
        enterDaily(board)
    }

    /// Resume an in-progress save if one exists for this day, else start fresh.
    private func enterDaily(_ board: DailyChallenge.Board) {
        navigator.activeDaily = board
        navigator.showingNewGame = false
        navigator.showingTitle = false
        if let snapshot = dailySaveStore.load(dateKey: board.dateKey) {
            viewModel.restore(from: snapshot)
        } else {
            viewModel.newGame(config: board.config, seed: board.seed, dateKey: board.dateKey)
        }
    }
}
