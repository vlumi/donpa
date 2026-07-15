import XCTest

@testable import DonpaCore

/// The shared-board derivation and the per-day record machinery.
final class DailyChallengeTests: XCTestCase {
    func testSameDateKeyIsTheSameBoardEverywhere() {
        let a = DailyChallenge.board(for: "2026-07-21")
        let b = DailyChallenge.board(for: "2026-07-21")
        XCTAssertEqual(a, b)
        XCTAssertNotNil(a)
        // The start cell sits inside the board.
        XCTAssertLessThan(a!.startCell.x, a!.config.width)
        XCTAssertLessThan(a!.startCell.y, a!.config.height)
    }

    func testDifferentDatesDiffer() {
        let a = DailyChallenge.board(for: "2026-07-21")
        let b = DailyChallenge.board(for: "2026-07-22")
        XCTAssertNotEqual(a?.seed, b?.seed)
    }

    func testPreEpochHasNoBoard() {
        XCTAssertNil(DailyChallenge.board(for: "2026-06-30"))
        XCTAssertNotNil(DailyChallenge.board(for: DailyChallenge.epochKey))
    }

    func testConfigPickIsDeterministicButNotAWeeklyCycle() {
        let picks = (0..<70).map { DailyChallenge.config(forOrdinal: $0) }
        XCTAssertEqual(picks, (0..<70).map { DailyChallenge.config(forOrdinal: $0) })
        // Not `ordinal % count`: somewhere in ten weeks the cycle must break.
        let weekly = (0..<70).map { DailyChallenge.pool[$0 % DailyChallenge.pool.count] }
        XCTAssertNotEqual(picks, weekly)
        // The whole pool still shows up over ten weeks.
        XCTAssertEqual(Set(picks).count, DailyChallenge.pool.count)
    }

    func testEveryBlockDealsTheWholePool() {
        let count = DailyChallenge.pool.count
        for block in 0..<20 {
            let picks = (0..<count).map {
                DailyChallenge.config(forOrdinal: block * count + $0)
            }
            XCTAssertEqual(Set(picks).count, count, "block \(block) skips a config")
        }
    }

    func testNoTwoConsecutiveDaysShareAConfig() {
        let picks = (0..<366).map { DailyChallenge.config(forOrdinal: $0) }
        for day in 1..<picks.count {
            XCTAssertNotEqual(picks[day], picks[day - 1], "day \(day) repeats its eve")
        }
    }

    func testStableHashNeverDrifts() {
        // Pinned value: a drift here would hand every player a new board.
        XCTAssertEqual(DailyChallenge.fnv1a("donpa.daily.2026-07-20"), 0x86C5_F095_0C39_F665)
    }

    func testScannedSeedLeavesStartZoneMineFree() {
        for ordinal in 0..<14 {
            guard let key = DailyMerge.dateKey(ordinal: ordinal),
                let board = DailyChallenge.board(for: key)
            else { return XCTFail("no board for ordinal \(ordinal)") }
            XCTAssertTrue(
                DailyChallenge.startZoneIsClear(
                    config: board.config, seed: board.seed, startCell: board.startCell),
                "day \(key): relocation must never fire")
        }
    }

    func testSeededGameFromFixedStartIsIdenticalAndOpens() async {
        guard let board = DailyChallenge.board(for: "2026-07-25") else {
            return XCTFail("no board")
        }
        var opened: [Int] = []
        for _ in 0..<2 {
            let game = await MainActor.run { () -> GameViewModel in
                let vm = GameViewModel(config: board.config)
                vm.newGame(config: board.config, seed: board.seed)
                return vm
            }
            // Arming computes off-main and gates input — an immediate reveal
            // would be dropped.
            await game.awaitPendingWork()
            await MainActor.run { game.reveal(board.startCell) }
            await game.awaitPendingWork()
            let count = await MainActor.run { game.game.revealedSafeCount }
            opened.append(count)
            let floods = await MainActor.run {
                game.game.board[board.startCell].adjacentMines == 0
            }
            XCTAssertTrue(floods, "first-click-safe guarantees a 0 at the fixed start")
        }
        XCTAssertEqual(opened[0], opened[1], "identical seed + start = identical opening")
        XCTAssertGreaterThan(opened[0], 1)
    }
}

/// Merge + streak math.
final class DailyMergeTests: XCTestCase {
    private func day(
        best: Int? = nil, ordinal: Int = 1, progress: Double? = nil, attempts: Int
    ) -> DailyDayRecord {
        var record = DailyDayRecord()
        for _ in 0..<attempts { record.attempts.add(1) }
        if let best {
            record.best = .init(centiseconds: best, threeBV: 50, attemptOrdinal: ordinal)
        }
        record.bestProgress = progress
        return record
    }

    func testMergeTakesFastestBestWithItsOrdinalAndSumsAttempts() {
        let own = ["d1": day(best: 500, ordinal: 3, attempts: 4)]
        let other = ["d1": day(best: 400, ordinal: 1, attempts: 2)]
        let merged = DailyMerge.merged(own: own, others: [other])
        XCTAssertEqual(merged["d1"]?.best?.centiseconds, 400)
        XCTAssertEqual(merged["d1"]?.best?.attemptOrdinal, 1, "ordinal rides with the winner")
        XCTAssertEqual(merged["d1"]?.attempts.total, 6)
    }

    func testMergeKeepsDaysOnlyOneSideHas() {
        let merged = DailyMerge.merged(
            own: ["d1": day(attempts: 1)], others: [["d2": day(progress: 0.5, attempts: 2)]])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged["d2"]?.bestProgress, 0.5)
        XCTAssertEqual(merged["d2"]?.attempts.total, 2)
    }

    func testCurrentStreakCountsBackFromTodayOrYesterday() {
        let d = { DailyMerge.dateKey(ordinal: $0)! }
        let played: Set<String> = [d(0), d(1), d(2)]
        XCTAssertEqual(DailyMerge.currentStreak(playedDays: played, today: d(2)), 3)
        // Today unplayed: the run ending yesterday still counts.
        XCTAssertEqual(DailyMerge.currentStreak(playedDays: played, today: d(3)), 3)
        // A gap ends it.
        XCTAssertEqual(DailyMerge.currentStreak(playedDays: played, today: d(5)), 0)
    }

    func testLongestStreakSpansGaps() {
        let d = { DailyMerge.dateKey(ordinal: $0)! }
        let played: Set<String> = [d(0), d(2), d(3), d(4), d(8)]
        XCTAssertEqual(DailyMerge.longestStreak(playedDays: played), 3)
    }
}

/// The store: attempt recording, persistence, sync gate.
@MainActor
final class DailyStoreTests: XCTestCase {
    private final class MockCloud: CloudDailyStore {
        var isAvailable = true
        var blobs: [String: Data] = [:]
        var onExternalChange: (() -> Void)?

        func writeOwnBlob(_ data: Data, deviceID: String) { blobs[deviceID] = data }
        func deleteOwnBlob(deviceID: String) { blobs[deviceID] = nil }
        func readAllBlobs() -> [String: Data] { blobs }
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "daily-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testAttemptsAccrueAndBestKeepsItsOrdinal() {
        let store = DailyStore(
            cloud: nil, deviceID: "a", syncEnabled: false, defaults: freshDefaults())
        store.recordAttempt(
            dateKey: "d1",
            .init(won: false, centiseconds: 0, threeBV: nil, progress: 0.4, live: true))
        store.recordAttempt(
            dateKey: "d1",
            .init(won: true, centiseconds: 900, threeBV: 40, progress: 1, live: true))
        store.recordAttempt(
            dateKey: "d1",
            .init(won: true, centiseconds: 1200, threeBV: 40, progress: 1, live: true))

        let day = store.displayRecords["d1"]
        XCTAssertEqual(day?.attempts.total, 3)
        XCTAssertEqual(day?.best?.centiseconds, 900)
        XCTAssertEqual(day?.best?.attemptOrdinal, 2, "the slower third attempt keeps 2")
        XCTAssertEqual(day?.bestProgress, 0.4)
    }

    func testPersistsAcrossInstances() {
        let defaults = freshDefaults()
        let store = DailyStore(cloud: nil, deviceID: "a", syncEnabled: false, defaults: defaults)
        store.recordAttempt(
            dateKey: "d1",
            .init(won: true, centiseconds: 500, threeBV: 30, progress: 1, live: true))

        let reloaded = DailyStore(
            cloud: nil, deviceID: "a", syncEnabled: false, defaults: defaults)
        XCTAssertEqual(reloaded.displayRecords["d1"]?.best?.centiseconds, 500)
    }

    func testSyncGatePushesAndRemovesBlob() {
        let cloud = MockCloud()
        let store = DailyStore(
            cloud: cloud, deviceID: "a", syncEnabled: true, defaults: freshDefaults())
        store.recordAttempt(
            dateKey: "d1",
            .init(won: false, centiseconds: 0, threeBV: nil, progress: 0.2, live: true))
        XCTAssertNotNil(cloud.blobs["a"])

        store.syncEnabled = false
        XCTAssertNil(cloud.blobs["a"])
    }

    func testCalendarReplayNeverRepairsAStreak() {
        let store = DailyStore(
            cloud: nil, deviceID: "a", syncEnabled: false, defaults: freshDefaults())
        store.recordAttempt(
            dateKey: "d-past",
            .init(won: true, centiseconds: 100, threeBV: 10, progress: 1, live: false))
        XCTAssertTrue(store.playedDays.isEmpty, "a replayed past day is not 'played'")
        XCTAssertEqual(store.displayRecords["d-past"]?.best?.centiseconds, 100)
    }

    func testCareerRollsUpPlayedClearedAndStreaks() {
        let store = DailyStore(
            cloud: nil, deviceID: "a", syncEnabled: false, defaults: freshDefaults())
        let today = DailyChallenge.dateKey()
        store.recordAttempt(
            dateKey: today,
            .init(won: true, centiseconds: 800, threeBV: 30, progress: 1, live: true))
        store.recordAttempt(
            dateKey: "2026-07-02",
            .init(won: false, centiseconds: 0, threeBV: nil, progress: 0.5, live: false))

        let career = store.career
        XCTAssertEqual(career.played, 2, "replayed past days count as played")
        XCTAssertEqual(career.cleared, 1)
        XCTAssertEqual(career.currentStreak, 1, "only the live day feeds the streak")
        XCTAssertEqual(career.longestStreak, 1)
    }

    func testMergesOtherDevicesBlobs() {
        let cloud = MockCloud()
        var otherDay = DailyDayRecord()
        otherDay.attempts.add(2)
        otherDay.best = .init(centiseconds: 300, threeBV: 20, attemptOrdinal: 2)
        cloud.blobs["b"] = DailyStore.encode(["d1": otherDay])

        let store = DailyStore(
            cloud: cloud, deviceID: "a", syncEnabled: true, defaults: freshDefaults())
        store.recordAttempt(
            dateKey: "d1",
            .init(won: true, centiseconds: 800, threeBV: 20, progress: 1, live: true))

        let day = store.displayRecords["d1"]
        XCTAssertEqual(day?.best?.centiseconds, 300)
        XCTAssertEqual(day?.attempts.total, 3)
        XCTAssertEqual(store.currentStreak(today: "d1"), 0, "d1 isn't a real date key")
    }
}
