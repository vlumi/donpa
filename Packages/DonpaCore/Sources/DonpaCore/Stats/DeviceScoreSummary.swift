import Foundation

/// One device's own contribution, totalled across configs — the "Scores by
/// device" row numbers. Reads each counter's `mine` side only: a device's
/// blob (or the local store) counts just what was played on it, so these
/// sums partition the household total with nothing double-counted.
public struct DeviceScoreSummary: Equatable, Sendable {
    public let wins: Int
    public let gamesPlayed: Int
    public let playtimeCentiseconds: Int

    public init(records: [String: ScoreRecord]) {
        wins = records.values.reduce(0) { $0 + $1.wins.mine }
        gamesPlayed = records.values.reduce(0) { $0 + $1.gamesPlayed.mine }
        playtimeCentiseconds = records.values.reduce(0) { $0 + $1.playtimeCentiseconds.mine }
    }
}
