import Foundation

public enum PlayDistribution {
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

    /// `fraction` is of the AXIS total: configs lacking the axis (Basic has no
    /// size/density) don't count, so shares still sum to 1 of what they measure.
    public struct Share: Equatable {
        public let label: String
        public let fraction: Double
    }

    /// Shares in the axis's canonical order, zero-value segments dropped; empty
    /// when nothing measured.
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

    public enum Axis: CaseIterable, Sendable {
        case family, size, density, edges

        var buckets: [String] {
            switch self {
            case .family: return BoardFamily.allCases.map(\.label)
            case .size: return BoardSize.allCases.map(\.label)
            case .density: return Density.allCases.map(\.label)
            case .edges: return BoardEdges.allCases.map(\.label)
            }
        }

        /// nil when the axis doesn't apply — except edges: every config buckets
        /// (Basic/Drills are inherently Flat), so that bar covers ALL play.
        func bucket(for config: GameConfig) -> String? {
            switch self {
            case .family: return config.family.label
            case .size: return config.size?.label
            case .density: return config.density?.label
            case .edges: return config.edges.label
            }
        }
    }
}
