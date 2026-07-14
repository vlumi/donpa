import Foundation

/// One finished game, as the achievement layer sees it — only the momentary
/// facts that vanish when the next game starts (everything else a feat could
/// need already lives in the score records).
public struct GameEndEvent: Equatable, Sendable {
    public let config: GameConfig
    public let won: Bool
    public let timeCentiseconds: Int
    /// Fraction of safe cells revealed (1 on a win).
    public let progress: Double
    /// Reveals + chords this game. Restore-poisoned: a resumed game reports a
    /// huge count, so momentary feats can never false-fire on it.
    public let revealActions: Int
    public let date: Date
    /// The board's 3BV (see `Pace.threeBV`); wins only, nil on losses.
    public let threeBV: Int?

    public init(
        config: GameConfig, won: Bool, timeCentiseconds: Int, progress: Double,
        revealActions: Int, date: Date, threeBV: Int? = nil
    ) {
        self.config = config
        self.won = won
        self.timeCentiseconds = timeCentiseconds
        self.progress = progress
        self.revealActions = revealActions
        self.date = date
        self.threeBV = threeBV
    }
}
