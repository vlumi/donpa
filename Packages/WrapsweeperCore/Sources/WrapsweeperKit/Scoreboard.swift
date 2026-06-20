import Foundation
import WrapsweeperCore

/// A single best-time record for one difficulty.
public struct ScoreRecord: Codable, Equatable, Sendable {
    public var seconds: Int
}

/// Local best-time-per-difficulty store, persisted in `UserDefaults`. No
/// security beyond the OS's per-app preferences file — a determined user can
/// edit it, which is fine for a local high-score table.
@MainActor
public final class Scoreboard: ObservableObject {
    @Published public private(set) var records: [String: ScoreRecord]

    private let defaults: UserDefaults
    private let key = "wrapsweeper.bestTimes"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([String: ScoreRecord].self, from: data)
        {
            records = decoded
        } else {
            records = [:]
        }
    }

    public func best(for difficulty: Difficulty) -> ScoreRecord? {
        records[difficulty.name]
    }

    /// True if `seconds` would beat (or set) the record for this difficulty.
    public func isNewRecord(_ seconds: Int, for difficulty: Difficulty) -> Bool {
        guard let existing = records[difficulty.name] else { return true }
        return seconds < existing.seconds
    }

    /// Record a winning time. No-op if it doesn't beat the existing best.
    @discardableResult
    public func submit(_ seconds: Int, for difficulty: Difficulty) -> Bool {
        guard isNewRecord(seconds, for: difficulty) else { return false }
        records[difficulty.name] = ScoreRecord(seconds: seconds)
        persist()
        return true
    }

    public func reset() {
        records = [:]
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: key)
        }
    }
}
