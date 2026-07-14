import Foundation

/// One analyzed action's outcome; `id` makes consecutive same-odds events
/// distinguishable to `onChange` observers.
public struct ForcedGuessEvent: Equatable, Sendable {
    /// Survival odds at the moment the action was taken (0...1).
    public let survival: Double
    public let survived: Bool
    public let id: Int
}

extension GameViewModel {
    /// The pre-action state for guess analysis, or nil when analysis can't apply
    /// (so the huge boards never retain a second board copy).
    func preGuessState() -> Game? {
        (game.status == .playing && game.board.cellCount <= GuessOdds.maxCells) ? game : nil
    }

    /// Compute the verdict off the main thread; a genuine forced guess is
    /// reported via `onForcedGuess` and published as `lastForcedGuess`.
    func reportGuess(survived: Bool, verdict: @escaping @Sendable () -> GuessOdds.Verdict?) {
        let config = self.config
        Task.detached(priority: .utility) { [weak self] in
            guard let verdict = verdict(), verdict.forced else { return }
            // Recaptured: referencing the outer `self` var from this second
            // concurrent closure is a Swift 6 error.
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
