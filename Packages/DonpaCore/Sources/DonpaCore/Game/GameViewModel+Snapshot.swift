import Foundation

extension GameViewModel {
    public var status: GameStatus { game.status }
    public var flagsRemaining: Int { game.flagsRemaining }
    public var boardWidth: Int { config.width }
    public var boardHeight: Int { config.height }

    /// A snapshot with the live timer span folded in; nil if there's nothing
    /// worth saving.
    public func snapshot() -> GameSnapshot? {
        GameSnapshot(
            game: game, config: config, elapsedCentiseconds: currentCentiseconds(),
            camera: cameraView, inputMode: inputMode)
    }

    /// The `Sendable` inputs a snapshot needs, captured cheaply on the main
    /// actor so the heavy board scan can run off it (see `GameSnapshot(inputs:)`).
    public struct SnapshotInputs: Sendable {
        public let game: Game
        public let config: GameConfig
        public let elapsedCentiseconds: Int
        public let camera: CameraView?
        public let inputMode: InputMode
    }

    public func snapshotInputs() -> SnapshotInputs? {
        guard game.status == .playing else { return nil }
        return SnapshotInputs(
            game: game, config: config, elapsedCentiseconds: currentCentiseconds(),
            camera: cameraView, inputMode: inputMode)
    }

    /// The launch-time board swap: a fresh board like `newGame`, but flagged as
    /// a placeholder so autosave doesn't read it as the player abandoning the
    /// config's saved game. Any player-initiated `newGame`/`restore` clears it.
    public func prime(config: GameConfig) {
        newGame(config: config)
        isPrimedBoard = true
    }
}
