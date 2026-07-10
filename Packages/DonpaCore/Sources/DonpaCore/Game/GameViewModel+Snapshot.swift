import Foundation

/// Snapshot capture, split from the main view model for the file-length budget
/// (restore stays beside the state it resets).
extension GameViewModel {
    /// A snapshot of the current game (live timer span folded in for an exact
    /// elapsed), or nil if there's nothing worth saving.
    public func snapshot() -> GameSnapshot? {
        GameSnapshot(
            game: game, config: config, elapsedCentiseconds: currentCentiseconds(),
            camera: cameraView, inputMode: inputMode)
    }

    /// The `Sendable` inputs a snapshot needs, captured cheaply on the main actor so
    /// the actual snapshot BUILD (which scans the whole board to derive the
    /// revealed/flagged coord sets — heavy on a 1M-cell board) can run OFF the main
    /// thread (see `GameSnapshot(inputs:)`).
    public struct SnapshotInputs: Sendable {
        public let game: Game
        public let config: GameConfig
        public let elapsedCentiseconds: Int
        public let camera: CameraView?
        public let inputMode: InputMode
    }

    /// Capture the snapshot inputs, or nil unless a save is worthwhile (in progress).
    public func snapshotInputs() -> SnapshotInputs? {
        guard game.status == .playing else { return nil }
        return SnapshotInputs(
            game: game, config: config, elapsedCentiseconds: currentCentiseconds(),
            camera: cameraView, inputMode: inputMode)
    }

    /// The launch-time board swap: a fresh board like `newGame`, but flagged as the
    /// placeholder it is — the player never asked for it, so autosave must not
    /// treat it as the player having abandoned the config's saved game. (It did:
    /// the priming `newGame`'s revision bump scheduled a debounced autosave whose
    /// clear-branch deleted the last-selected config's save ~2s after every
    /// launch.) Any player-initiated `newGame`/`restore` clears `isPrimedBoard`.
    public func prime(config: GameConfig) {
        newGame(config: config)
        isPrimedBoard = true
    }
}
