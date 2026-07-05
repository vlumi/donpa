import Foundation

/// Pure comparison logic for the scoreboard's friend features. Two shapes:
///
/// - **Per-config ranking** (`rank(config:)`): you + the selected rivals on one board,
///   ordered by best time (fastest first), with your position and the field size —
///   drives both the expanded interleave and the collapsed "N/M" badge.
/// - **Head-to-head** (`headToHead(...)`): across every board either side has cleared,
///   who is faster, plus the win/loss tally — drives the dedicated compare sheet.
///
/// Headless: takes plain figures (your best per config, rivals' `SharedConfigScore`),
/// no dependency on `Scoreboard` / `FriendsStore` / UI. Best time is centiseconds;
/// nil = never won (sorts last, never "wins" a comparison).
public enum ScoreComparison {
    /// One competitor's standing on a board: who, their best time (nil = unwon), and
    /// whether it's you. Sorted rows use this.
    public struct Entry: Equatable, Sendable {
        public let name: String
        /// Best winning time in centiseconds, or nil if never won this board.
        public let best: Int?
        public let isYou: Bool

        public init(name: String, best: Int?, isYou: Bool) {
            self.name = name
            self.best = best
            self.isYou = isYou
        }
    }

    /// A ranked board: every competitor ordered fastest-first (unwon last), plus your
    /// 1-based rank among those who HAVE a time (nil if you haven't won it) and the
    /// count of competitors with a time (the "M" in "N/M").
    public struct Ranking: Equatable, Sendable {
        public let entries: [Entry]
        /// Your 1-based position among ranked (won) competitors, or nil if you haven't
        /// won this board.
        public let yourRank: Int?
        /// How many competitors have a time here (the field you're ranked within).
        public let rankedCount: Int
    }

    /// Rank you + rivals on one board. `yourBest` is your best time (nil = unwon);
    /// `rivals` are (name, best) for each selected friend on this config.
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

    /// Who's ahead on a board in a head-to-head.
    public enum Lead: Equatable, Sendable { case you, them, tie, neither }

    /// One board's line in a head-to-head: your time, their time, and who's ahead.
    public struct HeadToHeadRow: Equatable, Sendable {
        public let configKey: String
        public let yourBest: Int?
        public let theirBest: Int?
        public let lead: Lead
    }

    /// A full head-to-head: per-board rows (only boards either side has a bearing on)
    /// plus the tally of boards each leads.
    public struct HeadToHead: Equatable, Sendable {
        public let rows: [HeadToHeadRow]
        public let youLead: Int
        public let theyLead: Int
    }

    /// Compare all your bests against one opponent's (a single friend, or a group's
    /// best-per-board already reduced to `theirBests`). `configKeys` is the union of
    /// boards to consider. Bests are keyed only where a board was WON — an absent key
    /// means unwon (no double-optionals).
    public static func headToHead(
        configKeys: [String], yourBests: [String: Int], theirBests: [String: Int]
    ) -> HeadToHead {
        var rows: [HeadToHeadRow] = []
        var youLead = 0
        var theyLead = 0
        for key in configKeys {
            let mine = yourBests[key]
            let theirs = theirBests[key]
            // Skip boards neither side has cleared — nothing to compare.
            guard mine != nil || theirs != nil else { continue }
            let lead = leadFor(mine: mine, theirs: theirs)
            if lead == .you { youLead += 1 }
            if lead == .them { theyLead += 1 }
            rows.append(
                HeadToHeadRow(configKey: key, yourBest: mine, theirBest: theirs, lead: lead))
        }
        return HeadToHead(rows: rows, youLead: youLead, theyLead: theyLead)
    }

    /// For a GROUP opponent, reduce members' scores to the group's best time per board
    /// (the fastest member), so the head-to-head is you vs "the group's best".
    public static func groupBests(_ membersScores: [[String: Int]]) -> [String: Int] {
        var best: [String: Int] = [:]
        for scores in membersScores {
            for (key, time) in scores {
                best[key] = min(best[key] ?? time, time)
            }
        }
        return best
    }

    // MARK: Ordering

    /// Fastest first; a missing time sorts after any real time. Ties break by name so
    /// the order is deterministic. `isYou` never affects order (only highlighting).
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
