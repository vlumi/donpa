import Foundation

/// Progressive gating: which parts of the New Game matrix a player has opened.
/// A pure predicate over the merged score records — no stored unlock set, no
/// event feed, no migration: veterans auto-pass because their records already
/// hold the wins, and sync is free because the records already sync. (See
/// ROADMAP "Progression spec" for the design; gates are ACCESS, not goals.)
///
/// Win credit: any won config credits its SIZE (Basic maps
/// Beginner/Intermediate/Expert → XS/S/M; Drills counts — the practice range
/// training you up is the point), its RANK when it has one and the board is
/// ≥ S, the Hive gate when it's a square family, and the Round gate when it's
/// ≥ M. Ladders are monotone on "or above": a win that arrives from higher up
/// (a rival's board via head-to-head, a share link) opens every rung at or
/// below it, so escape-hatch play can never wedge the ladder.
public enum UnlockEngine {
    /// What a locked option needs — the teaser's copy source.
    public enum Requirement: Equatable, Sendable {
        /// Win any board at this size or larger.
        case winSize(BoardSize)
        /// Win a board at this rank or denser, S or larger.
        case winRank(Density)
        /// Win any square-family board (Drills/Basic/Grid).
        case winAnySquare
        /// Win any board at M or larger.
        case winAtLeastM
    }

    // MARK: Axis predicates

    /// XS/S/M are open; each later rung opens on a credited win at (or above)
    /// the rung below it.
    public static func sizeUnlocked(_ size: BoardSize, records: [String: ScoreRecord]) -> Bool {
        guard let gate = sizeGate(size) else { return true }
        return credit(records).sizes.contains { $0 >= gate.index }
    }

    /// Trainee/Sapper are open; each denser rank opens on a credited (≥ S) win
    /// at (or above) the rank below it.
    public static func rankUnlocked(_ rank: Density, records: [String: ScoreRecord]) -> Bool {
        guard let gate = rankGate(rank) else { return true }
        return credit(records).ranks.contains { $0 >= gate.index }
    }

    /// Only Hive gates: it opens on the first credited square-family win.
    public static func familyUnlocked(_ family: BoardFamily, records: [String: ScoreRecord])
        -> Bool
    {
        family != .hive || credit(records).wonSquare
    }

    /// Only Round gates: it opens on the first credited win at ≥ M.
    public static func edgesUnlocked(_ edges: BoardEdges, records: [String: ScoreRecord]) -> Bool {
        edges != .round || credit(records).wonAtLeastM
    }

    /// The whole config: every axis it actually has must be open.
    public static func unlocked(_ config: GameConfig, records: [String: ScoreRecord]) -> Bool {
        familyUnlocked(config.family, records: records)
            && edgesUnlocked(config.edges, records: records)
            && (config.size.map { sizeUnlocked($0, records: records) } ?? true)
            && (config.density.map { rankUnlocked($0, records: records) } ?? true)
    }

    // MARK: Requirements (teaser copy)

    /// What opens this size — nil for the always-open starting rungs.
    public static func requirement(size: BoardSize) -> Requirement? {
        sizeGate(size).map { .winSize($0.rung) }
    }

    /// What opens this rank — nil for the always-open starting rungs.
    public static func requirement(rank: Density) -> Requirement? {
        rankGate(rank).map { .winRank($0.rung) }
    }

    /// What opens this family — nil unless it's the Hive.
    public static func requirement(family: BoardFamily) -> Requirement? {
        family == .hive ? .winAnySquare : nil
    }

    /// What opens these edges — nil unless they're Round.
    public static func requirement(edges: BoardEdges) -> Requirement? {
        edges == .round ? .winAtLeastM : nil
    }

    // MARK: The credit sweep

    /// Everything the records prove, in ladder-index form.
    private struct Credit {
        var sizes: Set<Int> = []  // credited size indices (BoardSize.allCases order)
        var ranks: Set<Int> = []  // credited rank indices (Density.allCases order)
        var wonSquare = false
        var wonAtLeastM = false
    }

    /// One pass over the config universe: collect what every won board credits.
    private static func credit(_ records: [String: ScoreRecord]) -> Credit {
        var credit = Credit()
        for config in universe where (records[config.storageKey]?.wins.total ?? 0) > 0 {
            guard let size = creditedSize(of: config) else { continue }
            let sizeIndex = BoardSize.allCases.firstIndex(of: size) ?? 0
            credit.sizes.insert(sizeIndex)
            if size >= .m { credit.wonAtLeastM = true }
            if config.family != .hive { credit.wonSquare = true }
            if let rank = config.density, size >= .s,
                let rankIndex = Density.allCases.firstIndex(of: rank)
            {
                credit.ranks.insert(rankIndex)
            }
        }
        return credit
    }

    /// The size a win credits: the config's own, or the Basic preset mapping
    /// (declared, geometry-spirited: Beginner = XS, Intermediate = S — exact
    /// geometry — Expert = M).
    private static func creditedSize(of config: GameConfig) -> BoardSize? {
        if case .basic(let preset) = config {
            switch preset {
            case .beginner: return .xs
            case .intermediate: return .s
            case .expert: return .m
            }
        }
        return config.size
    }

    /// Every config a record key could describe (the same sweep head-to-head
    /// uses): all families × both edges, deduped by key.
    private static let universe: [GameConfig] = {
        var seen = Set<String>()
        return BoardFamily.allCases.flatMap { family in
            BoardEdges.allCases.flatMap { edges in
                GameConfig.configs(family: family, edges: edges)
            }
        }.filter { seen.insert($0.storageKey).inserted }
    }()

    // MARK: The ladders

    /// The rung a locked size needs a win at (or above): the size below it.
    /// XS/S/M are open (nil).
    private static func sizeGate(_ size: BoardSize) -> (rung: BoardSize, index: Int)? {
        let all = BoardSize.allCases
        guard let i = all.firstIndex(of: size), size > .m else { return nil }
        return (all[i - 1], i - 1)
    }

    /// The rung a locked rank needs a (≥ S) win at (or above): the rank below.
    /// Trainee/Sapper are open (nil).
    private static func rankGate(_ rank: Density) -> (rung: Density, index: Int)? {
        let all = Density.allCases
        guard let i = all.firstIndex(of: rank), rank > .normal else { return nil }
        return (all[i - 1], i - 1)
    }
}

extension BoardSize: Comparable {
    public static func < (lhs: BoardSize, rhs: BoardSize) -> Bool {
        let all = BoardSize.allCases
        return (all.firstIndex(of: lhs) ?? 0) < (all.firstIndex(of: rhs) ?? 0)
    }
}

extension Density: Comparable {
    public static func < (lhs: Density, rhs: Density) -> Bool {
        let all = Density.allCases
        return (all.firstIndex(of: lhs) ?? 0) < (all.firstIndex(of: rhs) ?? 0)
    }
}
