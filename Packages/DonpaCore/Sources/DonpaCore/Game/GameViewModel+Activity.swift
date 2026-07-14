import Foundation

extension GameViewModel {
    /// Push the unflushed tiles/flags/time delta to the lifetime totals via
    /// `onActivityFlush`; a flush with nothing new to report does nothing.
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
