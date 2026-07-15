import Foundation

/// One day's aggregate — never per-attempt rows. Bests are device-owned
/// (the merge projects the cross-device winner, the BestTime pattern);
/// attempts is a `DeviceCounter` so counts sum across devices. The best's
/// attempt ordinal is stored but NOT displayed until device attribution can
/// qualify it — bare, it would read as a user-global sequence.
public struct DailyDayRecord: Codable, Equatable, Sendable {
    public struct Best: Codable, Equatable, Sendable {
        public var centiseconds: Int
        public var threeBV: Int
        /// The attempt ordinal ON THIS DEVICE when the best landed.
        public var attemptOrdinal: Int

        public var pace: Double {
            Double(threeBV) * 100 / Double(max(centiseconds, 1))
        }

        public init(centiseconds: Int, threeBV: Int, attemptOrdinal: Int) {
            self.centiseconds = centiseconds
            self.threeBV = threeBV
            self.attemptOrdinal = attemptOrdinal
        }
    }

    /// This device's fastest clear, or nil while never cleared here.
    public var best: Best?
    /// Best cleared fraction from a losing attempt (a win implies 100%).
    public var bestProgress: Double?
    public var attempts: DeviceCounter
    /// An attempt was completed ON the day itself — the only thing streaks
    /// count. Playing a past day from the calendar records results but can
    /// never repair a broken streak. Merges OR.
    public var playedLive: Bool

    public init(
        best: Best? = nil, bestProgress: Double? = nil, attempts: DeviceCounter = .init(),
        playedLive: Bool = false
    ) {
        self.best = best
        self.bestProgress = bestProgress
        self.attempts = attempts
        self.playedLive = playedLive
    }

    public var cleared: Bool { best != nil }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        best = try c.decodeIfPresent(Best.self, forKey: .best)
        bestProgress = try c.decodeIfPresent(Double.self, forKey: .bestProgress)
        attempts = try c.decodeIfPresent(DeviceCounter.self, forKey: .attempts) ?? .init()
        playedLive = try c.decodeIfPresent(Bool.self, forKey: .playedLive) ?? false
    }

    enum CodingKeys: String, CodingKey {
        case best = "b", bestProgress = "p", attempts = "a", playedLive = "l"
    }
}

/// Pure merge + streak logic over per-device day maps.
public enum DailyMerge {
    /// The cross-device view: per day, the fastest best wins (its ordinal
    /// rides along), progress is max, attempts sum as a G-counter (each
    /// blob's `mine` folds into the own record's `othersTotal`).
    public static func merged(
        own: [String: DailyDayRecord], others: [[String: DailyDayRecord]]
    ) -> [String: DailyDayRecord] {
        var out = own
        let days = Set(own.keys).union(others.flatMap(\.keys))
        for day in days {
            var record = own[day] ?? DailyDayRecord()
            var othersAttempts = 0
            for blob in others {
                guard let theirs = blob[day] else { continue }
                if let their = theirs.best,
                    their.centiseconds < (record.best?.centiseconds ?? .max)
                {
                    record.best = their
                }
                if let progress = theirs.bestProgress {
                    record.bestProgress = max(record.bestProgress ?? 0, progress)
                }
                record.playedLive = record.playedLive || theirs.playedLive
                othersAttempts += theirs.attempts.mine
            }
            record.attempts.setOthersTotal(othersAttempts)
            out[day] = record
        }
        return out
    }

    /// Consecutive played days ending today — or yesterday, so an unplayed
    /// today shows the streak still alive rather than zero.
    public static func currentStreak(playedDays: Set<String>, today: String) -> Int {
        guard let ordinal = DailyChallenge.dayOrdinal(of: today) else { return 0 }
        var cursor = playedDays.contains(today) ? ordinal : ordinal - 1
        var streak = 0
        while cursor >= 0, let key = dateKey(ordinal: cursor), playedDays.contains(key) {
            streak += 1
            cursor -= 1
        }
        return streak
    }

    /// The longest run anywhere in the history.
    public static func longestStreak(playedDays: Set<String>) -> Int {
        let ordinals = Set(playedDays.compactMap(DailyChallenge.dayOrdinal(of:)))
        var longest = 0
        for day in ordinals where !ordinals.contains(day - 1) {
            var length = 1
            while ordinals.contains(day + length) { length += 1 }
            longest = max(longest, length)
        }
        return longest
    }

    public static func dateKey(ordinal: Int) -> String? {
        guard let epoch = DailyChallenge.dayOrdinal(of: DailyChallenge.epochKey),
            epoch == 0
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let parts = DailyChallenge.epochKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
            let epochDate = calendar.date(
                from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
            let date = calendar.date(byAdding: .day, value: ordinal, to: epochDate)
        else { return nil }
        return DailyChallenge.dateKey(for: date, calendar: calendar)
    }
}
