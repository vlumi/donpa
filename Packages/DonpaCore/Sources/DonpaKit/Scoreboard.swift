import DonpaCore
import Foundation

/// Per-config stats: how many games have been cleared, the best time, and the
/// best partial progress (for boards rarely cleared outright).
public struct ScoreRecord: Codable, Equatable, Sendable {
    /// Total games cleared on this config.
    public var wins: Int
    /// Fastest winning time in centiseconds (hundredths), or nil if none yet.
    public var bestCentiseconds: Int?
    /// Best fraction (0...1) of safe cells revealed in a *losing* game. A win is
    /// implicitly 100%, so this only tracks losses; `wins > 0` means 100% at
    /// display time. Optional so old saved records (without it) decode cleanly.
    public var bestLossProgress: Double?

    public init(wins: Int = 0, bestCentiseconds: Int? = nil, bestLossProgress: Double? = nil) {
        self.wins = wins
        self.bestCentiseconds = bestCentiseconds
        self.bestLossProgress = bestLossProgress
    }
}

/// Local per-difficulty stats store (clears + best time), persisted in
/// `UserDefaults`. No security beyond the OS's per-app preferences file — a
/// determined user can edit it, which is fine for a local high-score table.
@MainActor
public final class Scoreboard: ObservableObject {
    @Published public private(set) var records: [String: ScoreRecord]

    private let defaults: UserDefaults
    // Key bumped from the old name-keyed store; entries are now keyed by
    // `GameConfig.storageKey` (geometry-bearing, versioned). Pre-release, so the
    // old store is simply not read — no migration by design.
    private let key = "donpa.stats.v1"

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

    public func record(for config: GameConfig) -> ScoreRecord? {
        records[config.storageKey]
    }

    /// Best time for this config, in centiseconds.
    public func best(for config: GameConfig) -> Int? {
        records[config.storageKey]?.bestCentiseconds
    }

    public func wins(for config: GameConfig) -> Int {
        records[config.storageKey]?.wins ?? 0
    }

    /// Best progress (0...1) to display for this config: 1.0 once the board has
    /// ever been cleared (a win is implicitly full), otherwise the best partial
    /// progress from a loss. `nil` if the config has never been finished.
    public func bestProgress(for config: GameConfig) -> Double? {
        guard let record = records[config.storageKey] else { return nil }
        if record.wins > 0 { return 1.0 }
        return record.bestLossProgress
    }

    /// True if `centiseconds` would beat (or set) the best time for this config.
    public func isNewRecord(_ centiseconds: Int, for config: GameConfig) -> Bool {
        guard let best = records[config.storageKey]?.bestCentiseconds else { return true }
        return centiseconds < best
    }

    /// Record a win: always bumps the clear count, and updates the best time if
    /// `centiseconds` beats it. Returns true if it set a new best time.
    @discardableResult
    public func submit(_ centiseconds: Int, for config: GameConfig) -> Bool {
        var record = records[config.storageKey] ?? ScoreRecord()
        record.wins += 1
        let isBest = record.bestCentiseconds.map { centiseconds < $0 } ?? true
        if isBest { record.bestCentiseconds = centiseconds }
        records[config.storageKey] = record
        persist()
        return isBest
    }

    /// Record the safe-cell progress (0...1) from a *losing* game, keeping it
    /// only if it beats the stored best loss-progress. Wins are recorded via
    /// `submit(_:for:)` (a win is implicitly 100%, so don't call this on a win).
    /// Returns true if it set a new best loss-progress.
    @discardableResult
    public func submitLossProgress(_ progress: Double, for config: GameConfig) -> Bool {
        var record = records[config.storageKey] ?? ScoreRecord()
        // A win is implicitly 100%, so once the board has ever been cleared a
        // loss can't be a "new best" — compare against the displayed best, which
        // is 1.0 when there's a win.
        let currentBest = record.wins > 0 ? 1.0 : (record.bestLossProgress ?? 0)
        let isBest = progress > currentBest
        if isBest {
            record.bestLossProgress = progress
            records[config.storageKey] = record
            persist()
        }
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
