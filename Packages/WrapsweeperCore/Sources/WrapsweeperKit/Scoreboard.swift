import Foundation
import WrapsweeperCore

/// Per-difficulty stats: how many games have been cleared, and the best time.
public struct ScoreRecord: Codable, Equatable, Sendable {
    /// Total games cleared on this difficulty.
    public var wins: Int
    /// Fastest winning time in seconds, or nil if none recorded yet.
    public var bestSeconds: Int?

    public init(wins: Int = 0, bestSeconds: Int? = nil) {
        self.wins = wins
        self.bestSeconds = bestSeconds
    }
}

/// Local per-difficulty stats store (clears + best time), persisted in
/// `UserDefaults`. No security beyond the OS's per-app preferences file — a
/// determined user can edit it, which is fine for a local high-score table.
@MainActor
public final class Scoreboard: ObservableObject {
    @Published public private(set) var records: [String: ScoreRecord]

    private let defaults: UserDefaults
    private let key = "wrapsweeper.stats"

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

    public func record(for difficulty: Difficulty) -> ScoreRecord? {
        records[difficulty.name]
    }

    public func best(for difficulty: Difficulty) -> Int? {
        records[difficulty.name]?.bestSeconds
    }

    public func wins(for difficulty: Difficulty) -> Int {
        records[difficulty.name]?.wins ?? 0
    }

    /// True if `seconds` would beat (or set) the best time for this difficulty.
    public func isNewRecord(_ seconds: Int, for difficulty: Difficulty) -> Bool {
        guard let best = records[difficulty.name]?.bestSeconds else { return true }
        return seconds < best
    }

    /// Record a win: always bumps the clear count, and updates the best time if
    /// `seconds` beats it. Returns true if it set a new best time.
    @discardableResult
    public func submit(_ seconds: Int, for difficulty: Difficulty) -> Bool {
        var record = records[difficulty.name] ?? ScoreRecord()
        record.wins += 1
        let isBest = record.bestSeconds.map { seconds < $0 } ?? true
        if isBest { record.bestSeconds = seconds }
        records[difficulty.name] = record
        persist()
        return isBest
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
