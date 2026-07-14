import Foundation

/// Pure comparison logic for the scoreboard's friend features: per-config ranking
/// (`rank`) and cross-board head-to-head (`headToHead`). Headless — takes plain
/// figures, no `Scoreboard`/`FriendsStore`/UI dependency. Times are centiseconds;
/// nil = never won (sorts last, never "wins" a comparison).
public enum ScoreComparison {
    public struct Entry: Equatable, Sendable {
        public let name: String
        public let best: Int?
        public let isYou: Bool

        public init(name: String, best: Int?, isYou: Bool) {
            self.name = name
            self.best = best
            self.isYou = isYou
        }
    }

    public struct Ranking: Equatable, Sendable {
        public let entries: [Entry]
        /// Your 1-based position among competitors with a time, or nil if you
        /// haven't won this board.
        public let yourRank: Int?
        /// How many competitors have a time here (the "M" in "N/M").
        public let rankedCount: Int
    }

    public static func rank(
        yourName: String, yourBest: Int?, rivals: [(name: String, best: Int?)]
    ) -> Ranking {
        var entries = [Entry(name: yourName, best: yourBest, isYou: true)]
        entries += rivals.map { Entry(name: $0.name, best: $0.best, isYou: false) }
        entries.sort(by: fasterFirst)

        let ranked = entries.filter { $0.best != nil }
        let yourRank = yourBest == nil ? nil : (ranked.firstIndex { $0.isYou }).map { $0 + 1 }
        return Ranking(entries: entries, yourRank: yourRank, rankedCount: ranked.count)
    }

    public enum Lead: Equatable, Sendable { case you, them, tie, neither }

    /// `holderName` is who on the other side holds that best for a group opponent
    /// (nil for a single rival). `gap` is yours minus theirs in centiseconds
    /// (negative = you faster), nil unless both have a time.
    public struct HeadToHeadRow: Equatable, Sendable {
        public let configKey: String
        public let yourBest: Int?
        public let theirBest: Int?
        public let lead: Lead
        public let holderName: String?
        public let gap: Int?
    }

    public struct HeadToHead: Equatable, Sendable {
        public let rows: [HeadToHeadRow]
        public let youLead: Int
        public let theyLead: Int
    }

    /// Rows cover only boards either side has a time on. Bests are keyed only where
    /// a board was WON — an absent key means unwon.
    public static func headToHead(
        configKeys: [String], yourBests: [String: Int], theirBests: [String: Int],
        theirHolders: [String: String] = [:]
    ) -> HeadToHead {
        var rows: [HeadToHeadRow] = []
        var youLead = 0
        var theyLead = 0
        for key in configKeys {
            let mine = yourBests[key]
            let theirs = theirBests[key]
            guard mine != nil || theirs != nil else { continue }
            let lead = leadFor(mine: mine, theirs: theirs)
            if lead == .you { youLead += 1 }
            if lead == .them { theyLead += 1 }
            let gap: Int? = (mine != nil && theirs != nil) ? mine! - theirs! : nil
            rows.append(
                HeadToHeadRow(
                    configKey: key, yourBest: mine, theirBest: theirs, lead: lead,
                    holderName: theirHolders[key], gap: gap))
        }
        return HeadToHead(rows: rows, youLead: youLead, theyLead: theyLead)
    }

    /// The group's best time per board and which member holds it, so a group
    /// head-to-head names the holder rather than being anonymous.
    public static func groupBests(
        _ members: [(name: String, scores: [String: Int])]
    ) -> (times: [String: Int], holders: [String: String]) {
        var best: [String: Int] = [:]
        var holder: [String: String] = [:]
        for member in members {
            for (key, time) in member.scores where time < (best[key] ?? .max) {
                best[key] = time
                holder[key] = member.name
            }
        }
        return (best, holder)
    }

    /// Fastest first; missing times sort last; ties break by name for determinism.
    private static func fasterFirst(_ a: Entry, _ b: Entry) -> Bool {
        switch (a.best, b.best) {
        case (let x?, let y?): return x != y ? x < y : a.name < b.name
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return a.name < b.name
        }
    }

    private static func leadFor(mine: Int?, theirs: Int?) -> Lead {
        switch (mine, theirs) {
        case (let x?, let y?): return x < y ? .you : (x > y ? .them : .tie)
        case (_?, nil): return .you
        case (nil, _?): return .them
        case (nil, nil): return .neither
        }
    }
}
