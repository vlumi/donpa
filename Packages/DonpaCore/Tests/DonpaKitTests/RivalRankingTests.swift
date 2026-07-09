import DonpaCore
import XCTest

@testable import DonpaKit

/// `RivalRanking.ranking` bridges the live stores to the pure `ScoreComparison`
/// for a board's best-time leaderboard. The rule under test: a rival with no
/// result on THIS board is left out — a best-time list shouldn't show "—" rows.
@MainActor
final class RivalRankingTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    /// A rival with the given per-config scores (pass `[]` for "never played it").
    private func rival(_ name: String, scores: [SharedConfigScore]) -> Friend {
        Friend(
            publicKey: Data(name.utf8), sharedName: name, lastIssuedAt: Date(),
            scores: scores, career: nil, addedAt: Date())
    }

    private func score(_ key: String, best: Int?) -> SharedConfigScore {
        SharedConfigScore(key: key, best: best, wins: best == nil ? 0 : 1, bestProgress: nil)
    }

    func testLeaderboardExcludesRivalsWithNoResultHere() {
        let config = GameConfig.basic(.beginner)
        let key = config.storageKey
        let scoreboard = Scoreboard(defaults: freshDefaults())
        scoreboard.submit(500, for: config)  // you have a time here

        let hasTime = rival("Amy", scores: [score(key, best: 810)])
        let noEntry = rival("Bob", scores: [])  // never played this board
        let playedNoWin = rival("Cara", scores: [score(key, best: nil)])  // played, never won

        let ranking = RivalRanking.ranking(
            config: config, scoreboard: scoreboard,
            rivals: [hasTime, noEntry, playedNoWin], yourName: "You")

        let names = Set(ranking.entries.map(\.name))
        XCTAssertTrue(names.contains("You"), "you always appear")
        XCTAssertTrue(names.contains("Amy"), "a rival with a time here is listed")
        XCTAssertFalse(names.contains("Bob"), "a rival who never played this board is hidden")
        XCTAssertFalse(
            names.contains("Cara"), "a rival who played but never won here is hidden")
    }

    func testYouStillAppearWithoutATime() {
        // A leaderboard on a board you haven't won still lists you (nil best), so
        // you can see the rivals you're chasing.
        let config = GameConfig.basic(.beginner)
        let scoreboard = Scoreboard(defaults: freshDefaults())
        let amy = rival("Amy", scores: [score(config.storageKey, best: 810)])

        let ranking = RivalRanking.ranking(
            config: config, scoreboard: scoreboard, rivals: [amy], yourName: "You")
        XCTAssertEqual(Set(ranking.entries.map(\.name)), ["You", "Amy"])
    }
}
