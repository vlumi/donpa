import DonpaCore
import XCTest

@testable import DonpaKit

/// `FriendRanking.ranking` bridges the live stores to the pure `ScoreComparison`
/// for a board's best-time leaderboard. The rule under test: a rival with no
/// result on THIS board is left out — a best-time list shouldn't show "—" rows.
@MainActor
final class FriendRankingTests: XCTestCase {
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
        scoreboard.submitWin(500, for: config)  // you have a time here

        let hasTime = rival("Amy", scores: [score(key, best: 810)])
        let noEntry = rival("Bob", scores: [])  // never played this board
        let playedNoWin = rival("Cara", scores: [score(key, best: nil)])  // played, never won

        let ranking = FriendRanking.ranking(
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

        let ranking = FriendRanking.ranking(
            config: config, scoreboard: scoreboard, rivals: [amy], yourName: "You")
        XCTAssertEqual(Set(ranking.entries.map(\.name)), ["You", "Amy"])
    }
}

/// The H2H daily rows and the share payload's daily window.
@MainActor
final class DailySharingTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    private func shared(
        _ key: String, best: Int? = nil, threeBV: Int? = nil, attempts: Int = 1
    ) -> SharedDailyDay {
        SharedDailyDay(key: key, best: best, threeBV: threeBV, progress: nil, attempts: attempts)
    }

    func testDailyRowsFollowTheRivalsWindowNewestFirst() {
        var mine = DailyDayRecord()
        mine.best = .init(centiseconds: 700, threeBV: 30, attemptOrdinal: 1)
        let rows = FriendRanking.dailyRows(
            yours: ["2026-07-20": mine, "2026-07-19": mine],  // 19th: your solo day
            theirs: [
                "2026-07-20": shared("2026-07-20", best: 900, threeBV: 30),
                "2026-07-21": shared("2026-07-21", best: 500, threeBV: 30),
            ])
        XCTAssertEqual(rows.map(\.key), ["2026-07-21", "2026-07-20"])
        XCTAssertEqual(rows[0].lead, .them, "their 500 vs your unplayed")
        XCTAssertEqual(rows[1].lead, .you, "your 700 beats their 900")
        XCTAssertNotNil(rows[1].theirPace)
    }

    func testDailyWindowTakesNewestDaysOldestFirst() {
        let store = DailyStore(
            cloud: nil, deviceID: "a", syncEnabled: false, defaults: freshDefaults())
        for day in 1...20 {
            store.recordAttempt(
                dateKey: String(format: "2026-06-%02d", day),
                .init(won: true, centiseconds: 1000 + day, threeBV: 30, progress: 1, live: false))
        }
        let window = SharePayloadBuilder.dailyWindow(from: store, days: 14)
        XCTAssertEqual(window?.count, 14)
        XCTAssertEqual(window?.first?.key, "2026-06-07", "the oldest kept day leads")
        XCTAssertEqual(window?.last?.key, "2026-06-20")
        XCTAssertEqual(window?.last?.best, 1020)

        XCTAssertEqual(SharePayloadBuilder.dailyWindow(from: store, days: nil)?.count, 20)
        let empty = DailyStore(
            cloud: nil, deviceID: "a", syncEnabled: false, defaults: freshDefaults())
        XCTAssertNil(SharePayloadBuilder.dailyWindow(from: empty, days: 14), "nothing to tell")
    }
}
