import Foundation

/// Activity flushing: pushing the unflushed tiles/flags/time DELTA to the lifetime
/// totals so they accrue without a per-tile write storm. Split from `GameViewModel`
/// for the file-length budget (see also +Timer / +Snapshot / +Guess).
extension GameViewModel {
    /// Flush this game's activity delta via `onActivityFlush`. Idempotent — a flush
    /// with nothing new to report does nothing.
    public func flushActivity() {
        let tiles = game.revealedSafeCount
        let flags = flagsPlacedThisGame
        let centi = currentCentiseconds()
        let dt = tiles - flushedTiles
        let df = flags - flushedFlags
        let dc = centi - flushedCentiseconds
        guard dt != 0 || df != 0 || dc != 0 else { return }
        flushedTiles = tiles
        flushedFlags = flags
        flushedCentiseconds = centi
        onActivityFlush?(dt, df, dc)
    }
}
