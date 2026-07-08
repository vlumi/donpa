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
}
