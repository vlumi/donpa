import Foundation

/// The curated feat list — IDs are PERMANENT once shipped (they become Game
/// Center definitions and sync-blob keys), so add but never rename. The full
/// content design — titles, floors, the one-sitting cap, what's deliberately
/// absent — lives in ROADMAP's "Progression spec".
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

    /// Tier thresholds for the tiered feats (bronze/silver/gold laurels in the
    /// Decorations grid; one Game Center definition per tier). nil = one-shot.
    public var tierThresholds: [Int]? {
        switch self {
        // Seconds, descending bars. Tuned to sit with the rest of the set ("skilled
        // but attainable"), not world-record: <3 min = you can win Expert, <90 s =
        // genuinely fast — no world-class speedrun tier that towered over the others.
        case .speedExpert: return [180, 120, 90]
        case .milesWins: return [10, 100, 1000]
        case .milesTiles: return [10_000, 100_000, 1_000_000]
        case .milesDisarmed: return [1000, 10_000, 100_000]
        default: return nil
        }
    }

    /// Hidden feats render as "?" until earned (and use ASC's hidden flag).
    public var isHidden: Bool {
        switch self {
        case .hiddenSecond, .hiddenThirteen, .hiddenSoClose, .hiddenOvertime: return true
        default: return false
        }
    }
}

/// The running value behind a tracked feat, for the detail view. `metric` tells
/// the UI how to phrase `current` (e.g. "472 wins", "1:23 best", "25% luck");
/// `thresholds` (from the id) lets it show the next rung if it wants.
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

/// Pure feat evaluation (A2 of the progression spec) — two modes, one engine:
/// `derivable` recomputes from the synced score records (retroactive: veterans
/// get stamped on first launch, a cloud restore recovers them), `momentary`
/// matches the single game-end instant for the feats no record can prove.
/// The store (A3) owns persistence; this owns only the rules.
public enum AchievementEngine {
    /// Everything the records prove: id → earned tier count (1 for one-shots,
    /// 1...n for tiered feats). Absent = nothing earned.
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
        // ONE luck decoration — surviving the canonical 50/50 (the toast tiers
        // and the luckiest-escape stat track anything rarer; degrees of luck
        // aren't degrees of merit). Same epsilon as the toasts, so exactly-1/2
        // counts.
        let eps = 1e-9
        if let luckiest = facts.luckiestSurvival {
            award(.luckCoinFlip, luckiest <= 0.5 + eps)
        }
        award(.fullClearSize, facts.anyFullClearedSize)
        award(.trifecta, facts.trifectaDone)
        if let total = facts.trifectaTotalCentiseconds {
            award(.trifectaTime, facts.trifectaDone && total < 30_000)  // under 5:00
        }
        // speed.expert: tier bars are "under N seconds" on the classic Expert best.
        if let best = facts.expertBestCentiseconds {
            let count = (AchievementID.speedExpert.tierThresholds ?? [])
                .filter { best < $0 * 100 }.count
            if count > 0 { earned[.speedExpert] = count }
        }
        tiers(.milesWins, value: facts.totalWins)
        tiers(.milesTiles, value: facts.totalTiles)
        tiers(.milesDisarmed, value: facts.totalDisarmed)
        return earned
    }

    /// The feats only the game-end instant can prove (stored once earned; the
    /// restore-poisoned action clock keeps resumed games out).
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

    /// The live value behind a TRACKED feat, for the detail view — so a tiered
    /// milestone shows "472 wins" (and thus which tier you're at) rather than
    /// leaving the medal colour as the only cue. nil for feats with no meaningful
    /// running number (one-shots, the hidden gags). The UI formats by `metric`.
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
            // The Expert best (nil until you've won one) — the value the tier bars
            // race against.
            return facts.expertBestCentiseconds.map {
                AchievementProgress(metric: .bestSeconds, current: $0)
            }
        case .luckCoinFlip:
            // Your luckiest survival so far, as a whole-percent (lower = luckier).
            return facts.luckiestSurvival.map {
                AchievementProgress(metric: .luckPercent, current: Int(($0 * 100).rounded()))
            }
        default:
            return nil
        }
    }

    // MARK: The record sweep

    /// One pass over the config universe, everything the rules read.
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

        /// The purity floor: ≥ M and Sapper-or-denser — a rank the config must
        /// HAVE, which structurally excludes Drills and Basic.
        var noFlagWinAtFloor: Bool {
            universe.contains { config, record in
                record.noFlagWins.total > 0 && config.size ?? .xs >= .m
                    && config.density ?? .easy >= .normal
            }
        }

        var luckiestSurvival: Double? {
            universe.compactMap { $0.record.luckiestGuess?.survival }.min()
        }

        /// Any (family × edges × size) leaf with every rank won. No size ceiling:
        /// full-clearing XXXL is strictly harder than L, so a player who only
        /// plays big boards earns it too (the old ≤ L cap punished exactly the
        /// harder path — lifted 2026-07-10).
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

        /// Sum of the three classic bests (nil until all three exist).
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
