import DonpaCore
import SwiftUI

/// Bridges the live stores to the pure `ScoreComparison`.
@MainActor
enum FriendRanking {
    static func rivals(from friends: FriendsStore, group groupID: String?) -> [Friend] {
        guard let groupID else { return friends.friends }
        return friends.members(of: groupID)
    }

    /// Rank you + the given rivals on one config, by best time.
    static func ranking(
        config: GameConfig, scoreboard: Scoreboard, rivals: [Friend], yourName: String
    ) -> ScoreComparison.Ranking {
        let key = config.storageKey
        // Only rivals with a time on this board rank; you always appear, even without one.
        let standings = rivals.compactMap { friend -> ScoreComparison.RivalStanding? in
            guard let score = friend.scores.first(where: { $0.key == key }),
                let best = score.best
            else { return nil }
            return ScoreComparison.RivalStanding(
                name: friend.displayName, best: best, bestPace: score.bestPace)
        }
        return ScoreComparison.rank(
            yourName: yourName, yourBest: scoreboard.best(for: config),
            yourBestPace: scoreboard.displayRecords[key]?.bestPace?.pace,
            rivals: standings)
    }

    // MARK: Head-to-head

    /// Every config across families/edges — the universe of boards to consider.
    static let allConfigs: [GameConfig] = BoardFamily.allCases.flatMap { family in
        BoardEdges.allCases.flatMap { edges in GameConfig.configs(family: family, edges: edges) }
    }
    private static let configByKey: [String: GameConfig] = Dictionary(
        allConfigs.map { ($0.storageKey, $0) }, uniquingKeysWith: { first, _ in first })

    /// A labeled head-to-head row. `holderName` names who on the other side holds
    /// `theirBest` (group compare only); `gap` is your signed delta (negative = faster).
    struct H2HRow: Identifiable {
        let key: String
        let config: GameConfig
        let yourBest: Int?
        let theirBest: Int?
        let yourBestPace: Double?
        let theirBestPace: Double?
        let lead: ScoreComparison.Lead
        let holderName: String?
        let gap: Int?
        var id: String { key }
    }

    struct H2H {
        let rows: [H2HRow]
        let youLead: Int
        let theyLead: Int
    }

    /// One family+edges run of the head-to-head, for the sheet's sticky sub-sections.
    struct H2HGroup: Identifiable {
        let family: BoardFamily
        let edges: BoardEdges
        let rows: [H2HRow]
        var id: String { "\(family.rawValue)|\(edges.rawValue)" }
    }

    /// Chunk rows into family+edges groups. Rows arrive contiguous per group (the
    /// canonical config order is family-outer, edges-inner), so this is a single pass.
    static func grouped(_ rows: [H2HRow]) -> [H2HGroup] {
        var out: [H2HGroup] = []
        for row in rows {
            let family = row.config.family
            let edges = row.config.edges
            if let last = out.last, last.family == family, last.edges == edges {
                out[out.count - 1] = H2HGroup(
                    family: family, edges: edges, rows: last.rows + [row])
            } else {
                out.append(H2HGroup(family: family, edges: edges, rows: [row]))
            }
        }
        return out
    }

    private static func yourBests(_ scoreboard: Scoreboard) -> [String: Int] {
        var out: [String: Int] = [:]
        for config in allConfigs where scoreboard.best(for: config) != nil {
            out[config.storageKey] = scoreboard.best(for: config)
        }
        return out
    }

    private static func bests(of friend: Friend) -> [String: Int] {
        var out: [String: Int] = [:]
        for score in friend.scores {
            if let best = score.best { out[score.key] = best }
        }
        return out
    }

    private static func yourPaces(_ scoreboard: Scoreboard) -> [String: Double] {
        scoreboard.displayRecords.compactMapValues { $0.bestPace?.pace }
    }

    private static func paces(of friend: Friend) -> [String: Double] {
        var out: [String: Double] = [:]
        for score in friend.scores {
            if let pace = score.bestPace { out[score.key] = pace }
        }
        return out
    }

    static func headToHead(
        with friend: Friend, scoreboard: Scoreboard
    ) -> H2H {
        labeled(
            ScoreComparison.headToHead(
                configKeys: Array(configByKey.keys),
                yourBests: yourBests(scoreboard), theirBests: bests(of: friend),
                yourPaces: yourPaces(scoreboard), theirPaces: paces(of: friend)))
    }

    /// Head-to-head against a group's best (fastest member per board).
    static func headToHead(
        withGroup members: [Friend], scoreboard: Scoreboard
    ) -> H2H {
        let group = ScoreComparison.groupBests(
            members.map { (name: $0.displayName, scores: bests(of: $0)) })
        return labeled(
            ScoreComparison.headToHead(
                configKeys: Array(configByKey.keys),
                yourBests: yourBests(scoreboard), theirBests: group.times,
                yourPaces: yourPaces(scoreboard),
                theirPaces: ScoreComparison.groupBestPaces(members.map { paces(of: $0) }),
                theirHolders: group.holders))
    }

    /// Attach board configs, dropping rows whose key can't resolve (unknown/legacy
    /// configs), in the app's canonical config order.
    private static func labeled(_ h: ScoreComparison.HeadToHead) -> H2H {
        let order = Dictionary(
            allConfigs.enumerated().map { ($0.element.storageKey, $0.offset) },
            uniquingKeysWith: { first, _ in first })
        let rows =
            h.rows
            .compactMap { row -> H2HRow? in
                guard let config = configByKey[row.configKey] else { return nil }
                return H2HRow(
                    key: row.configKey, config: config,
                    yourBest: row.yourBest, theirBest: row.theirBest,
                    yourBestPace: row.yourBestPace, theirBestPace: row.theirBestPace,
                    lead: row.lead, holderName: row.holderName, gap: row.gap)
            }
            .sorted { (order[$0.key] ?? .max) < (order[$1.key] ?? .max) }
        return H2H(rows: rows, youLead: h.youLead, theyLead: h.theyLead)
    }
}
