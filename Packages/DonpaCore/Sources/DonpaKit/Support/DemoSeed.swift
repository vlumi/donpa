import DonpaCore
import Foundation

/// Populates the stores with believable demo data for the screenshot harness
/// (`-uitest-demo`), so gallery and App Store captures show a real player's
/// app — scores across boards, a couple of rivals, a daily streak — rather
/// than empty state. Never runs outside that launch arg; ships inert.
@MainActor
enum DemoSeed {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-demo")
    }

    /// Seed once at launch. Times are hand-picked to look earned, not random,
    /// and to sort into a satisfying spread on the Service Record.
    static func apply(
        scoreboard: Scoreboard, friends: FriendsStore, daily: DailyStore, settings: Settings
    ) {
        seedScores(scoreboard)
        seedRivals(friends, settings: settings)
        seedDaily(daily)
    }

    /// One seeded board result: a best time, a win count, and the 3BV that
    /// drives its pace line.
    private struct Run {
        let config: GameConfig
        let best: Int
        let wins: Int
        let threeBV: Int
    }

    /// One seeded rival's clear on a board.
    private struct RivalScore {
        let config: GameConfig
        let best: Int
    }

    /// Best times + a plausible win/loss history across a representative
    /// spread of the config matrix (the presets, a couple of Grid/Hive sizes).
    private static func seedScores(_ scoreboard: Scoreboard) {
        let runs: [Run] = [
            Run(config: .basic(.beginner), best: 812, wins: 40, threeBV: 22),
            Run(config: .basic(.intermediate), best: 4_355, wins: 18, threeBV: 96),
            Run(config: .basic(.expert), best: 11_920, wins: 9, threeBV: 214),
            Run(config: .grid(.s, .normal, .flat), best: 1_640, wins: 12, threeBV: 38),
            Run(config: .grid(.m, .hard, .flat), best: 8_770, wins: 5, threeBV: 168),
            Run(config: .grid(.s, .normal, .round), best: 2_010, wins: 7, threeBV: 41),
            Run(config: .hive(.s, .normal, .flat), best: 1_890, wins: 10, threeBV: 44),
            Run(config: .hive(.m, .normal, .flat), best: 6_240, wins: 4, threeBV: 121),
        ]
        for run in runs {
            _ = scoreboard.submit(run.best, for: run.config, threeBV: run.threeBV)
            for _ in 0..<run.wins {
                _ = scoreboard.submit(run.best + 600, for: run.config, threeBV: run.threeBV)
            }
            scoreboard.recordGameOutcome(
                for: run.config, won: true, minesHit: 0,
                minesDisarmed: run.config.mineCount, chordsUsed: run.wins)
            // A few losses too, so the career reads like real play.
            scoreboard.recordGameOutcome(
                for: run.config, won: false, minesHit: 1, minesDisarmed: 0, chordsUsed: 1)
        }
    }

    /// Two rivals via signed payloads (the only way in — the store applies
    /// real shares), each with a handful of times so the head-to-head reads.
    private static func seedRivals(_ friends: FriendsStore, settings: Settings) {
        settings.shareName = "You"
        let rosters: [(name: String, scores: [RivalScore])] = [
            (
                "Aoi",
                [
                    RivalScore(config: .basic(.beginner), best: 744),
                    RivalScore(config: .basic(.expert), best: 13_050),
                    RivalScore(config: .hive(.s, .normal, .flat), best: 2_120),
                ]
            ),
            (
                "Rei",
                [
                    RivalScore(config: .basic(.beginner), best: 905),
                    RivalScore(config: .basic(.intermediate), best: 3_980),
                    RivalScore(config: .grid(.m, .hard, .flat), best: 8_010),
                ]
            ),
        ]
        for roster in rosters {
            let identity = ShareIdentity()
            let scores = roster.scores.map { entry in
                SharedConfigScore(
                    key: entry.config.storageKey, best: entry.best, wins: 5,
                    bestProgress: nil, recentPace: nil, bestPace: nil)
            }
            if let payload = try? identity.makePayload(
                name: roster.name, scores: scores, career: nil, issuedAt: Date())
            {
                _ = friends.apply(payload)
            }
        }
    }

    /// A short live streak ending today, plus a couple of earlier days, so the
    /// Home card and calendar show a run rather than "not played yet".
    private static func seedDaily(_ daily: DailyStore) {
        let today = DailyChallenge.dayOrdinal(of: DailyChallenge.dateKey()) ?? 0
        for back in 0..<5 {
            guard let key = DailyMerge.dateKey(ordinal: today - back) else { continue }
            daily.recordAttempt(
                dateKey: key,
                .init(
                    won: true, centiseconds: 1_500 + back * 120, threeBV: 40, progress: 1,
                    live: true))
        }
    }
}
