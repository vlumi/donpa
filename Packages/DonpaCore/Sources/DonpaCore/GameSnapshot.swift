import Foundation

/// A compact, `Codable` capture of an in-progress game, for save/restore across
/// app launches. Stores the *config* (which carries the topology kind + params,
/// so the existential `any Topology` is never encoded) plus the placed mine
/// layout and the revealed/flagged cells as coordinate sets — far smaller than
/// the full cell dictionary, and the safe path on huge boards.
///
/// Versioned so a format change can be detected and an incompatible save simply
/// discarded rather than mis-decoded.
public struct GameSnapshot: Codable, Sendable {
    /// Bump when the shape changes incompatibly; decoder rejects other versions.
    public static let currentVersion = 1

    public let version: Int
    public let config: GameConfig
    public let mines: Set<Coord>
    public let revealed: Set<Coord>
    public let flagged: Set<Coord>
    public let status: GameStatus
    public let revealedSafeCount: Int
    public let lossCoord: Coord?
    /// Banked play time; the live span is always folded in before saving.
    public let elapsedCentiseconds: Int

    /// Capture a snapshot of a live game. Returns nil for a game not worth saving
    /// (not started, or already finished) — only a genuine in-progress game is.
    public init?(game: Game, config: GameConfig, elapsedCentiseconds: Int) {
        guard game.status == .playing else { return nil }
        self.version = Self.currentVersion
        self.config = config
        self.mines = game.board.mineCoords
        self.revealed = game.board.revealedCoords
        self.flagged = game.board.flaggedCoords
        self.status = game.status
        self.revealedSafeCount = game.revealedSafeCount
        self.lossCoord = game.lossCoord
        self.elapsedCentiseconds = elapsedCentiseconds
    }

    /// Rebuild the `Game` this snapshot describes (topology from the config).
    public func makeGame() -> Game {
        Game.restored(from: self)
    }
}
