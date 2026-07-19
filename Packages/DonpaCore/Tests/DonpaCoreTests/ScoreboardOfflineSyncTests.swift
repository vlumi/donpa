import XCTest

@testable import DonpaCore

/// The OFFLINE half of the sync state machine: the display must never freeze at
/// the cached snapshot, deletes must not silently vanish, and stale caches must
/// not resurrect wiped data. Uses `FakeCloud` (ScoreboardSyncTests.swift) with
/// its per-device `available` switch as airplane mode.
@MainActor
final class ScoreboardOfflineSyncTests: XCTestCase {
    private func defaults(_ id: String) -> UserDefaults {
        UserDefaults(suiteName: "offline-\(id)-\(UUID().uuidString)")!
    }

    // MARK: Display follows offline play

    func testOfflineSubmitShowsImmediately() {
        let shared = FakeCloud.Shared()
        let aCloud = FakeCloud(shared: shared)
        let a = Scoreboard(defaults: defaults("a"), cloud: aCloud)
        let b = Scoreboard(defaults: defaults("b"), cloud: FakeCloud(shared: shared))
        b.submitWin(250, for: .beginner)  // A caches the merge with B's win

        aCloud.available = false  // airplane mode
        a.submitWin(300, for: .beginner)
        XCTAssertEqual(a.wins(for: .beginner), 2, "own offline win + B's cached win")
        XCTAssertEqual(a.best(for: .beginner), 250, "cached cross-device best survives")
    }

    func testOfflineResetShowsImmediately() {
        let shared = FakeCloud.Shared()
        let aCloud = FakeCloud(shared: shared)
        let a = Scoreboard(defaults: defaults("a"), cloud: aCloud)
        let b = Scoreboard(defaults: defaults("b"), cloud: FakeCloud(shared: shared))
        a.submitWin(300, for: .beginner)
        b.submitWin(250, for: .beginner)

        aCloud.available = false
        a.reset()
        XCTAssertEqual(a.wins(for: .beginner), 1, "own contribution gone; B's cached win stays")
    }

    func testOfflineRelaunchShowsFreshOwnRecords() {
        let shared = FakeCloud.Shared()
        let aDefaults = defaults("a")
        let aCloud = FakeCloud(shared: shared)
        let a = Scoreboard(defaults: aDefaults, cloud: aCloud)
        let b = Scoreboard(defaults: defaults("b"), cloud: FakeCloud(shared: shared))
        b.submitWin(250, for: .beginner)
        aCloud.available = false
        a.submitWin(300, for: .beginner)

        // Relaunch, still offline: the fresh own win must show, not the stale cache.
        let a2 = Scoreboard(
            defaults: aDefaults, cloud: FakeCloud(shared: shared, available: false))
        XCTAssertEqual(a2.wins(for: .beginner), 2, "offline launch projects own over cache")
    }

    // MARK: Own loss progress is device-owned (like best times)

    func testLossProgressStoredPerDeviceSurvivesOtherDeviceReset() {
        let shared = FakeCloud.Shared()
        let a = Scoreboard(defaults: defaults("a"), cloud: FakeCloud(shared: shared))
        let b = Scoreboard(defaults: defaults("b"), cloud: FakeCloud(shared: shared))
        a.submitLossProgress(0.9, for: .expert)
        XCTAssertFalse(b.submitLossProgress(0.7, for: .expert), "not a cross-device best")

        a.reset()  // A's 0.9 leaves the board
        XCTAssertEqual(
            b.bestProgress(for: .expert) ?? 0, 0.7, accuracy: 1e-9,
            "B's own 0.7 was stored even while A was ahead — no regression to older data")
    }

    func testLossProgressStampsPlayedDates() {
        let a = Scoreboard(defaults: defaults("a"), cloud: FakeCloud())
        a.submitLossProgress(0.4, for: .expert)
        XCTAssertNotNil(a.record(for: .expert)?.lastPlayed, "a loss counts as having played")
    }

    // MARK: Dropped cloud deletes are replayed

    func testSyncOffWhileOfflineDeletesBlobOnReconnect() {
        let shared = FakeCloud.Shared()
        let aCloud = FakeCloud(shared: shared)
        let a = Scoreboard(defaults: defaults("a"), cloud: aCloud)
        a.submitWin(300, for: .beginner)
        XCTAssertEqual(shared.blobs.count, 1)

        aCloud.available = false
        a.syncEnabled = false
        XCTAssertEqual(shared.blobs.count, 1, "offline: the delete couldn't run yet")

        aCloud.available = true
        a.refreshFromCloud()  // the foreground hook replays the pending delete
        XCTAssertTrue(shared.blobs.isEmpty, "the ghost blob is cleaned on reconnect")
    }

    func testOfflineResetPropagatesOnReconnect() {
        let shared = FakeCloud.Shared()
        let aCloud = FakeCloud(shared: shared)
        let a = Scoreboard(defaults: defaults("a"), cloud: aCloud)
        let b = Scoreboard(defaults: defaults("b"), cloud: FakeCloud(shared: shared))
        a.submitWin(300, for: .beginner)
        b.submitWin(250, for: .beginner)

        aCloud.available = false
        a.reset()
        XCTAssertEqual(b.wins(for: .beginner), 2, "B still counts A's stale blob while offline")

        aCloud.available = true
        a.refreshFromCloud()  // foreground re-push propagates the reset
        XCTAssertEqual(b.wins(for: .beginner), 1, "A's contribution drops on reconnect")
    }

    // MARK: Tombstone vs the sync toggle

    func testEnablingSyncAfterRemoteWipeWarnsThenHonorsTombstone() {
        let shared = FakeCloud.Shared()
        let a = Scoreboard(
            defaults: defaults("a"), cloud: FakeCloud(shared: shared), syncEnabled: false)
        a.submitWin(300, for: .beginner)  // deliberate local-only play
        let b = Scoreboard(defaults: defaults("b"), cloud: FakeCloud(shared: shared))
        b.submitWin(250, for: .beginner)
        XCTAssertTrue(b.wipeAllSynced(), "B plants the global tombstone")

        XCTAssertEqual(a.wins(for: .beginner), 1, "sync-off device keeps local data")
        XCTAssertTrue(a.enablingSyncWouldWipeLocal, "…and the UI can warn before enabling")

        a.syncEnabled = true
        XCTAssertEqual(a.wins(for: .beginner), 0, "opting in honors the tombstone")
        XCTAssertFalse(a.enablingSyncWouldWipeLocal)
    }

    // MARK: Stale caches never resurrect

    func testStaleEpochCacheIsNotShownOnOfflineLaunch() {
        let aDefaults = defaults("a")
        // A pre-upgrade merged cache: no epoch stamp = epoch 0, below the floor.
        let key = GameConfig.beginner.storageKey
        let stale = #"{"version":1,"records":{"\#(key)":{"wins":{"mine":7}}}}"#
        aDefaults.set(Data(stale.utf8), forKey: "donpa.stats.merged.v1")

        let a = Scoreboard(defaults: aDefaults, cloud: FakeCloud(available: false))
        XCTAssertEqual(a.wins(for: .beginner), 0, "a pre-floor cache must not resurrect")
    }
}
