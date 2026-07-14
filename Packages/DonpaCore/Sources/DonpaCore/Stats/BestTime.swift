import Foundation

/// A winning time paired with WHEN it was achieved. The timestamp travels with
/// its value so merging can never separate them: the display picks whole
/// `BestTime`s, never mins the times and dates apart. Stored UTC.
public struct BestTime: Equatable, Sendable, Codable {
    public var centiseconds: Int
    /// Wall-clock at record time; labeling, not ordering.
    public var achievedAt: Date

    public init(centiseconds: Int, achievedAt: Date) {
        self.centiseconds = centiseconds
        self.achievedAt = achievedAt
    }

    enum CodingKeys: String, CodingKey { case centiseconds = "cs", achievedAt = "at" }
}

extension Array where Element == BestTime {
    /// The cross-device top `limit`, fastest first, de-duplicated on the whole
    /// (time, date) entry — the same clear must not count twice when lists overlap.
    public func mergedTop(with others: [[BestTime]], limit: Int) -> [BestTime] {
        var all = self
        for list in others { all.append(contentsOf: list) }
        var seen = Set<String>()
        let unique = all.filter { entry in
            let key = "\(entry.centiseconds)@\(entry.achievedAt.timeIntervalSince1970)"
            return seen.insert(key).inserted
        }
        return Array(unique.sorted { $0.centiseconds < $1.centiseconds }.prefix(limit))
    }

    /// Insert into this device's OWN top list; returns whether it made the cut.
    @discardableResult
    public mutating func insertTop(_ time: BestTime, limit: Int) -> Bool {
        append(time)
        sort { $0.centiseconds < $1.centiseconds }
        if count > limit { removeLast(count - limit) }
        return contains(time)
    }
}
