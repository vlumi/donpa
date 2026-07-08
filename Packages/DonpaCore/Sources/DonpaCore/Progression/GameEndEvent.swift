import Foundation

/// One finished game, as the achievement layer sees it (A1 of the progression
/// spec). Everything else a feat could need — purity bits, luck records, career
/// counters — already lives in the score records; this carries only the
/// momentary facts that vanish when the next game starts.
public struct GameEndEvent: Equatable, Sendable {
    public let config: GameConfig
    public let won: Bool
    /// The final clock, centiseconds.
    public let timeCentiseconds: Int
    /// Fraction of safe cells revealed (1 on a win).
    public let progress: Double
    /// Reveal-type actions this game (reveals + chords) — "lose on your second
    /// reveal" reads this. Restore-poisoned: a resumed game reports a huge
    /// count, so momentary feats can never false-fire on it.
    public let revealActions: Int
    public let date: Date

    public init(
        config: GameConfig, won: Bool, timeCentiseconds: Int, progress: Double,
        revealActions: Int, date: Date
    ) {
        self.config = config
        self.won = won
        self.timeCentiseconds = timeCentiseconds
        self.progress = progress
        self.revealActions = revealActions
        self.date = date
    }
}
