import Foundation

/// Pure helpers for the off-main compute path, split from the main view model for
/// the file-length budget. Both are read-only / static — no state mutation — so
/// they live cleanly outside the type body.
extension GameViewModel {
    /// What a finishing off-main compute should do, decided purely so it's testable
    /// (the async closure just applies the result, with no branching of its own).
    /// - `finished`: the gameID the finishing task belongs to.
    /// - `current`: the live gameID now.
    /// - `latestStarted`: the gameID of the most recently *started* compute.
    ///
    /// `applyResult` — only the live task (`finished == current`) writes its board +
    /// runs afterApply; a stale task (a newGame/restore bumped gameID past it) must
    /// not clobber the newer game.
    /// `releaseGate` — release `isComputing` for the live task, OR for a stale task
    /// when no newer compute is arming the current generation (`latestStarted !=
    /// current`); otherwise that newer compute owns the release. So the gate can
    /// never wedge shut regardless of which entry point bumped gameID.
    static func computeOutcome(finished: Int, current: Int, latestStarted: Int)
        -> (applyResult: Bool, releaseGate: Bool)
    {
        let live = finished == current
        return (applyResult: live, releaseGate: live || latestStarted != current)
    }

    /// The momentary end-of-game facts for the achievement layer.
    func event(finalCentiseconds: Int) -> GameEndEvent {
        GameEndEvent(
            config: config, won: game.status == .won,
            timeCentiseconds: finalCentiseconds, progress: game.progress,
            revealActions: revealActionsThisGame, date: Date())
    }
}
