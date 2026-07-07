import Foundation

/// One analyzed action's outcome, for in-the-moment UI feedback. `id` makes
/// consecutive same-odds events distinguishable to `onChange` observers.
public struct ForcedGuessEvent: Equatable, Sendable {
    /// Survival odds the action had at the moment it was taken (0...1).
    public let survival: Double
    /// Whether the player walked away from it.
    public let survived: Bool
    public let id: Int
}

/// The forced-guess analysis plumbing (see `GuessOdds`), split from
/// `GameViewModel` for the file-length budget.
extension GameViewModel {
    /// The pre-action state for guess analysis, or nil when analysis can't apply
    /// (so the huge boards never retain a second board copy).
    func preGuessState() -> Game? {
        (game.status == .playing && game.board.cellCount <= GuessOdds.maxCells) ? game : nil
    }

    /// Compute a completed reveal/chord's verdict off the main thread; when it was
    /// a genuine forced guess, report it via `onForcedGuess` (the stats hook) and
    /// publish it as `lastForcedGuess` (the UI feedback). Internal for the wiring
    /// test.
    func reportGuess(survived: Bool, verdict: @escaping @Sendable () -> GuessOdds.Verdict?) {
        let config = self.config
        Task.detached(priority: .utility) { [weak self] in
            guard let verdict = verdict(), verdict.forced else { return }
            // Recaptured immutably — referencing the outer `self` var from this
            // second concurrent closure is a Swift 6 error.
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.guessEventCounter += 1
                self.lastForcedGuess = ForcedGuessEvent(
                    survival: verdict.survival, survived: survived, id: self.guessEventCounter)
                self.onForcedGuess?(config, verdict.survival, survived)
            }
        }
    }
}
