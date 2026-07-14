import Foundation

extension GameViewModel {
    /// What a finishing off-main compute should do (pure, for testability).
    /// Only the live task (`finished == current`) applies its result — a stale
    /// one must not clobber a newer game. The gate releases for the live task,
    /// or for a stale one when no newer compute is arming the current
    /// generation (`latestStarted != current`) — so it can never wedge shut.
    static func computeOutcome(finished: Int, current: Int, latestStarted: Int)
        -> (applyResult: Bool, releaseGate: Bool)
    {
        let live = finished == current
        return (applyResult: live, releaseGate: live || latestStarted != current)
    }

    /// The end-of-game facts for the achievement layer. 3BV is computed on
    /// wins only — one linear pass at the game-end instant.
    func event(finalCentiseconds: Int) -> GameEndEvent {
        let won = game.status == .won
        return GameEndEvent(
            config: config, won: won,
            timeCentiseconds: finalCentiseconds, progress: game.progress,
            revealActions: revealActionsThisGame, date: Date(),
            threeBV: won ? Pace.threeBV(of: game.board) : nil)
    }
}
