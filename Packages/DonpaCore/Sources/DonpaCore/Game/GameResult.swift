public enum GameResult: Equatable, Sendable {
    case won(centiseconds: Int, config: GameConfig)
    case lost(at: Coord?)

    public var isWin: Bool { if case .won = self { return true } else { return false } }
}

/// A result tagged with a monotonic id, so observers fire on identical
/// outcomes in a row.
public struct GameResultEvent: Equatable, Sendable {
    public let id: Int
    public let result: GameResult
}
