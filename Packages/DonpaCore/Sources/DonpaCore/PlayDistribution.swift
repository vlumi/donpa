import Foundation

/// How play spreads across the config axes — family, size, density — by playtime or
/// game count. A pure aggregation over per-config figures; the Service Record's
/// breakdown bars are a straight rendering of these shares.
public enum PlayDistribution {
    /// One config's contribution, extracted by the caller from its score record.
    public struct Entry {
        public let config: GameConfig
        public let games: Int
        public let playtimeCentiseconds: Int

        public init(config: GameConfig, games: Int, playtimeCentiseconds: Int) {
            self.config = config
            self.games = games
            self.playtimeCentiseconds = playtimeCentiseconds
        }
    }

    public enum Metric: Hashable, Sendable {
        case playtime, games
    }

    /// One bar segment: an axis value's share of the total. `fraction` is of the
    /// AXIS total (family shares sum to 1; size/density cover Grid+Hive only, since
    /// Basic has no size/density tier — their shares still sum to 1 of what they
    /// measure).
    public struct Share: Equatable {
        public let label: String
        public let fraction: Double
    }

    /// Shares along one axis, in the axis's canonical order (families / XS→XXXL /
    /// easy→insane), zero-value segments dropped. Empty when nothing measured.
    public static func shares(
        entries: [Entry], metric: Metric, axis: Axis
    ) -> [Share] {
        var totals: [(label: String, value: Int)] = axis.buckets.map { ($0, 0) }
        for entry in entries {
            guard let bucket = axis.bucket(for: entry.config),
                let index = totals.firstIndex(where: { $0.label == bucket })
            else { continue }
            totals[index].value += value(of: entry, metric: metric)
        }
        let grand = totals.reduce(0) { $0 + $1.value }
        guard grand > 0 else { return [] }
        return totals.compactMap { label, value in
            value > 0 ? Share(label: label, fraction: Double(value) / Double(grand)) : nil
        }
    }

    private static func value(of entry: Entry, metric: Metric) -> Int {
        switch metric {
        case .playtime: return entry.playtimeCentiseconds
        case .games: return entry.games
        }
    }

    /// The three bars. Size/density apply to Grid+Hive only (Basic's presets have
    /// no tier on those axes), so those bars describe the configurable families.
    public enum Axis: CaseIterable, Sendable {
        case family, size, density

        /// The axis's canonical bucket labels, in display order.
        var buckets: [String] {
            switch self {
            case .family: return BoardFamily.allCases.map(\.label)
            case .size: return BoardSize.allCases.map(\.label)
            case .density: return Density.allCases.map(\.label)
            }
        }

        /// The bucket a config contributes to, or nil when the axis doesn't apply.
        func bucket(for config: GameConfig) -> String? {
            switch self {
            case .family: return config.family.label
            case .size: return config.size?.label
            case .density: return config.density?.label
            }
        }
    }
}
