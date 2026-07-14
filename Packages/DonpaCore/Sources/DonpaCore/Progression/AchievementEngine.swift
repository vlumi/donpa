import Foundation

/// IDs are PERMANENT once shipped (Game Center definitions and sync-blob keys):
/// add, never rename. Content design: DECISIONS.md "Progression".
public enum AchievementID: String, CaseIterable, Sendable {
    // Starters & identity
    case winFirst = "win.first"
    case drillsL = "drills.l"
    case hiveFirst = "hive.first"
    case roundFirst = "round.first"
    case hiveInsane = "hive.insane"
    // Skill & mastery
    case purityNoFlag = "purity.noflag"
    case speedExpert = "speed.expert"
    case insaneWin = "insane.win"
    case lunaticWin = "lunatic.win"
    // Luck (retroactive via the luckiest-guess record)
    case luckCoinFlip = "luck.coinflip"
    // Full-clear tie-ins
    case fullClearSize = "fullclear.size"
    case trifecta = "trifecta"
    case trifectaTime = "trifecta.time"
    // Milestones (tiered)
    case milesWins = "miles.wins"
    case milesTiles = "miles.tiles"
    case milesDisarmed = "miles.disarmed"
    // Hidden (momentary)
    case hiddenSecond = "hidden.second"
    case hiddenThirteen = "hidden.thirteen"
    case hiddenSoClose = "hidden.soclose"
    case hiddenOvertime = "hidden.overtime"

    /// nil = one-shot. Only VOLUME feats tier; skill thresholds deliberately
    /// don't ladder (that's the scoreboard's job).
    public var tierThresholds: [Int]? {
        switch self {
        case .milesWins: return [10, 100, 1000]
        case .milesTiles: return [10_000, 100_000, 1_000_000]
        case .milesDisarmed: return [1000, 10_000, 100_000]
        default: return nil
        }
    }

    /// Renders as "?" until earned (and uses ASC's hidden flag).
    public var isHidden: Bool {
        switch self {
        case .hiddenSecond, .hiddenThirteen, .hiddenSoClose, .hiddenOvertime: return true
        default: return false
        }
    }
}

/// The running value behind a tracked feat; `metric` tells the UI how to
/// phrase `current`.
public struct AchievementProgress: Equatable, Sendable {
    public enum Metric: Sendable {
        case wins
        case tiles
        case mines
        /// A best time in centiseconds (speed feats).
        case bestSeconds
        /// Luckiest survival as a whole percent (lower is luckier).
        case luckPercent
    }
    public let metric: Metric
    public let current: Int
}

/// Pure feat evaluation: `derivable` recomputes from the synced score records
/// (retroactive — veterans and cloud restores get stamped), `momentary` matches
/// the game-end instant for feats no record can prove. `AchievementStore` owns
/// persistence; this owns only the rules.
public enum AchievementEngine {
    /// id → earned tier count (1 for one-shots). Absent = nothing earned.
    public static func derivable(records: [String: ScoreRecord]) -> [AchievementID: Int] {
        let facts = Facts(records: records)
        var earned: [AchievementID: Int] = [:]
        func award(_ id: AchievementID, _ condition: Bool) {
            if condition { earned[id] = 1 }
        }
        func tiers(_ id: AchievementID, value: Int) {
            let count = (id.tierThresholds ?? []).filter { value >= $0 }.count
            if count > 0 { earned[id] = count }
        }

        award(.winFirst, facts.anyWin)
        award(.drillsL, facts.won { $0 == .practice(.l) })
        award(.hiveFirst, facts.won { $0.family == .hive })
        award(.roundFirst, facts.won { $0.edges == .round })
        award(
            .hiveInsane,
            facts.won { $0.family == .hive && $0.density == .insane && $0.size ?? .xs >= .m })
        award(.purityNoFlag, facts.noFlagWinAtFloor)
        award(.insaneWin, facts.won { $0.density == .insane && $0.size ?? .xs >= .m })
        award(.lunaticWin, facts.won { $0.density == .lunatic })
        // ONE luck decoration — degrees of luck aren't degrees of merit. Same
        // epsilon as the toasts, so exactly-1/2 counts.
        let eps = 1e-9
        if let luckiest = facts.luckiestSurvival {
            award(.luckCoinFlip, luckiest <= 0.5 + eps)
        }
        award(.fullClearSize, facts.anyFullClearedSize)
        award(.trifecta, facts.trifectaDone)
        if let total = facts.trifectaTotalCentiseconds {
            award(.trifectaTime, facts.trifectaDone && total < 30_000)  // under 5:00
        }
        // speed.expert: one rite-of-passage bar; elite speed lives in the scoreboard.
        if let best = facts.expertBestCentiseconds {
            award(.speedExpert, best < 180 * 100)
        }
        tiers(.milesWins, value: facts.totalWins)
        tiers(.milesTiles, value: facts.totalTiles)
        tiers(.milesDisarmed, value: facts.totalDisarmed)
        return earned
    }

    /// Feats only the game-end instant can prove. The restore-poisoned action
    /// clock keeps resumed games out.
    public static func momentary(_ event: GameEndEvent) -> [AchievementID] {
        var earned: [AchievementID] = []
        if !event.won, event.revealActions == 2 { earned.append(.hiddenSecond) }
        if event.won, (1300...1399).contains(event.timeCentiseconds) {
            earned.append(.hiddenThirteen)
        }
        if !event.won, event.progress >= 0.99 { earned.append(.hiddenSoClose) }
        if event.won, event.timeCentiseconds > 99_900 { earned.append(.hiddenOvertime) }
        return earned
    }

    /// nil for feats with no meaningful running number (one-shots, hidden gags).
    public static func progress(for id: AchievementID, records: [String: ScoreRecord])
        -> AchievementProgress?
    {
        let facts = Facts(records: records)
        switch id {
        case .milesWins:
            return AchievementProgress(metric: .wins, current: facts.totalWins)
        case .milesTiles:
            return AchievementProgress(metric: .tiles, current: facts.totalTiles)
        case .milesDisarmed:
            return AchievementProgress(metric: .mines, current: facts.totalDisarmed)
        case .speedExpert:
            return facts.expertBestCentiseconds.map {
                AchievementProgress(metric: .bestSeconds, current: $0)
            }
        case .luckCoinFlip:
            return facts.luckiestSurvival.map {
                AchievementProgress(metric: .luckPercent, current: Int(($0 * 100).rounded()))
            }
        default:
            return nil
        }
    }

    // MARK: The record sweep

    /// One pass over the config universe: everything the rules read.
    private struct Facts {
        let records: [String: ScoreRecord]
        private let universe: [(config: GameConfig, record: ScoreRecord)]

        init(records: [String: ScoreRecord]) {
            self.records = records
            var seen = Set<String>()
            self.universe = BoardFamily.allCases.flatMap { family in
                BoardEdges.allCases.flatMap { edges in
                    GameConfig.configs(family: family, edges: edges)
                }
            }
            .filter { seen.insert($0.storageKey).inserted }
            .compactMap { config in records[config.storageKey].map { (config, $0) } }
        }

        var anyWin: Bool { universe.contains { $0.record.wins.total > 0 } }

        func won(_ matches: (GameConfig) -> Bool) -> Bool {
            universe.contains { $0.record.wins.total > 0 && matches($0.config) }
        }

        /// The purity floor: ≥ M and Sapper-or-denser — requiring a rank
        /// structurally excludes Drills and Basic.
        var noFlagWinAtFloor: Bool {
            universe.contains { config, record in
                record.noFlagWins.total > 0 && config.size ?? .xs >= .m
                    && config.density ?? .easy >= .normal
            }
        }

        var luckiestSurvival: Double? {
            universe.compactMap { $0.record.luckiestGuess?.survival }.min()
        }

        /// Any (family × edges × size) leaf with every rank won. Deliberately no
        /// size ceiling: full-clearing XXXL is strictly harder than L.
        var anyFullClearedSize: Bool {
            for family in [BoardFamily.grid, .hive] {
                for edges in BoardEdges.allCases {
                    for size in BoardSize.allCases {
                        let cleared = Density.allCases.allSatisfy { density in
                            guard let config = GameConfig.custom(family, size, density, edges)
                            else { return false }
                            return (records[config.storageKey]?.wins.total ?? 0) > 0
                        }
                        if cleared { return true }
                    }
                }
            }
            return false
        }

        var trifectaDone: Bool {
            BasicPreset.allCases.allSatisfy {
                (records[GameConfig.basic($0).storageKey]?.wins.total ?? 0) > 0
            }
        }

        /// nil until all three classic bests exist.
        var trifectaTotalCentiseconds: Int? {
            let bests = BasicPreset.allCases.compactMap {
                records[GameConfig.basic($0).storageKey]?.bestCentiseconds
            }
            return bests.count == BasicPreset.allCases.count
                ? bests.reduce(0, +) : nil
        }

        var expertBestCentiseconds: Int? {
            records[GameConfig.basic(.expert).storageKey]?.bestCentiseconds
        }

        var totalWins: Int { universe.reduce(0) { $0 + $1.record.wins.total } }
        var totalTiles: Int { universe.reduce(0) { $0 + $1.record.tilesOpened.total } }
        var totalDisarmed: Int { universe.reduce(0) { $0 + $1.record.minesDisarmed.total } }
    }
}
