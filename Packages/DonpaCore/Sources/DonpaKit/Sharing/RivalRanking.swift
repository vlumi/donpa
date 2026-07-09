import DonpaCore
import SwiftUI

/// Bridges the live stores to the pure `ScoreComparison`: builds a per-config ranking
/// (you + the selected rivals) and picks the rivals set from the friends list, honoring
/// an optional group filter. `@MainActor` because it reads `Scoreboard`/`FriendsStore`.
@MainActor
enum RivalRanking {
    /// The friends to compare against: everyone, or just one group's members.
    static func rivals(from friends: FriendsStore, group groupID: String?) -> [Friend] {
        guard let groupID else { return friends.friends }
        return friends.members(of: groupID)
    }

    /// Rank you + the given rivals on one config, by best time. `yourName` falls back to
    /// a generic label when you haven't set a share name.
    static func ranking(
        config: GameConfig, scoreboard: Scoreboard, rivals: [Friend], yourName: String
    ) -> ScoreComparison.Ranking {
        let key = config.storageKey
        // A best-time leaderboard only lists rivals who actually have a time here —
        // a rival who never won this board adds no ranking, only "—" clutter. (You
        // always appear, even without a time, so you can see where you stand.)
        let rivalPairs = rivals.compactMap { friend -> (name: String, best: Int?)? in
            guard let best = friend.scores.first(where: { $0.key == key })?.best else {
                return nil
            }
            return (name: friend.displayName, best: best)
        }
        return ScoreComparison.rank(
            yourName: yourName, yourBest: scoreboard.best(for: config), rivals: rivalPairs)
    }

    // MARK: Head-to-head

    /// Every config across families/edges, keyed by `storageKey` — the label source for
    /// head-to-head rows and the universe of boards to consider.
    static let allConfigs: [GameConfig] = BoardFamily.allCases.flatMap { family in
        BoardEdges.allCases.flatMap { edges in GameConfig.configs(family: family, edges: edges) }
    }
    private static let configByKey: [String: GameConfig] = Dictionary(
        allConfigs.map { ($0.storageKey, $0) }, uniquingKeysWith: { first, _ in first })

    /// A labeled head-to-head row: carries the full `GameConfig` so the sheet can
    /// render the board like the Service Record does (insignia + names) and start a
    /// game on it. `holderName` names who on the other side holds `theirBest` (group
    /// compare only); `gap` is your signed delta vs. theirs (negative = you faster).
    struct H2HRow: Identifiable {
        let key: String
        let config: GameConfig
        let yourBest: Int?
        let theirBest: Int?
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

    /// One family+edges run of the head-to-head, for the sheet's sticky sub-section
    /// titles — the group carries the family/edge identity so the rows can stay as
    /// slim as the Service Record's (insignia + size).
    struct H2HGroup: Identifiable {
        let family: BoardFamily
        let edges: BoardEdges
        let rows: [H2HRow]
        var id: String { "\(family.rawValue)|\(edges.rawValue)" }
    }

    /// Chunk canonical-ordered rows into their family+edges groups. Rows arrive
    /// already contiguous per group (the canonical config order is family-outer,
    /// edges-inner), so this is a single pass.
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

    /// Your best time per config key (only boards you've won).
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

    /// Head-to-head against a single friend.
    static func headToHead(
        with friend: Friend, scoreboard: Scoreboard
    ) -> H2H {
        labeled(
            ScoreComparison.headToHead(
                configKeys: Array(configByKey.keys),
                yourBests: yourBests(scoreboard), theirBests: bests(of: friend)))
    }

    /// Head-to-head against a group's best (fastest member per board), naming who holds
    /// each board's best so it isn't anonymous.
    static func headToHead(
        withGroup members: [Friend], scoreboard: Scoreboard
    ) -> H2H {
        let group = ScoreComparison.groupBests(
            members.map { (name: $0.displayName, scores: bests(of: $0)) })
        return labeled(
            ScoreComparison.headToHead(
                configKeys: Array(configByKey.keys),
                yourBests: yourBests(scoreboard), theirBests: group.times,
                theirHolders: group.holders))
    }

    /// Attach board configs + keep the tally; drop rows whose key we can't resolve
    /// (unknown/legacy configs), then order by the app's canonical config order.
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
                    yourBest: row.yourBest, theirBest: row.theirBest, lead: row.lead,
                    holderName: row.holderName, gap: row.gap)
            }
            .sorted { (order[$0.key] ?? .max) < (order[$1.key] ?? .max) }
        return H2H(rows: rows, youLead: h.youLead, theyLead: h.theyLead)
    }
}
