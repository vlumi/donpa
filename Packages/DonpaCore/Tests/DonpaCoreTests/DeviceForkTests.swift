import XCTest

@testable import DonpaCore

/// The staged fork: applied before stores exist, provenance moves, totals
/// never do. These tests stand in for a real device migration — the cloud is
/// never written by the fork itself, and the household numbers must read
/// identically before and after.
@MainActor
final class DeviceForkTests: XCTestCase {
    private func defaults(_ tag: String = "") -> UserDefaults {
        UserDefaults(suiteName: "fork-\(tag)-\(UUID().uuidString)")!
    }

    // MARK: The staged apply

    func testApplyIsANoOpUnlessStaged() {
        let d = defaults()
        let id = DeviceID.current(in: d)
        d.set(Data("stats".utf8), forKey: Scoreboard.localStoreKey)
        let marker = FakeInstallMarker(stored: "original")

        XCTAssertFalse(DeviceFork.applyIfPending(in: d, marker: marker))
        XCTAssertEqual(DeviceID.current(in: d), id)
        XCTAssertNotNil(d.data(forKey: Scoreboard.localStoreKey))
        XCTAssertEqual(marker.stored, "original")
    }

    func testApplyRemintsIdentityAndResetsTheCountedLocals() {
        let d = defaults()
        let oldID = DeviceID.current(in: d)
        d.set(Data("stats".utf8), forKey: Scoreboard.localStoreKey)
        d.set(Data("cache".utf8), forKey: StatsSyncCoordinator.mergedCacheKey)
        d.set(Data("daily".utf8), forKey: DailyStore.localStoreKey)
        let marker = FakeInstallMarker(stored: "old-hardware")

        DeviceFork.stage(in: d)
        XCTAssertTrue(DeviceFork.isPending(in: d))
        XCTAssertTrue(DeviceFork.applyIfPending(in: d, marker: marker))

        XCTAssertNotEqual(DeviceID.current(in: d), oldID, "a fresh identity")
        XCTAssertNil(d.data(forKey: Scoreboard.localStoreKey), "scores reset")
        XCTAssertNil(d.data(forKey: StatsSyncCoordinator.mergedCacheKey), "stale cache dropped")
        XCTAssertNil(d.data(forKey: DailyStore.localStoreKey), "daily counters reset")
        XCTAssertNotEqual(marker.stored, "old-hardware", "a fresh install marker")
        XCTAssertTrue(d.bool(forKey: CloneDetection.markerMintedKey))
        XCTAssertFalse(DeviceFork.isPending(in: d), "one-shot")
        XCTAssertFalse(DeviceFork.applyIfPending(in: d, marker: marker), "idempotent")
    }

    func testForkedInstallReadsEstablishedNotMigrated() {
        let d = defaults()
        _ = DeviceID.current(in: d)
        let marker = FakeInstallMarker()
        DeviceFork.stage(in: d)
        _ = DeviceFork.applyIfPending(in: d, marker: marker)
        XCTAssertEqual(CloneDetection.bootstrap(defaults: d, marker: marker), .established)
    }

    // MARK: End to end over a fake cloud — the "real migration" stand-in

    func testForkPreservesHouseholdTotalsAndReassignsProvenance() {
        let shared = FakeCloud.Shared()
        let d = defaults("a")

        // Life before the fork: three wins, pushed to the cloud.
        let before = Scoreboard(defaults: d, cloud: FakeCloud(shared: shared))
        let oldID = before.ownDeviceID
        before.submitWin(300, for: .beginner)
        before.submitWin(250, for: .beginner)
        before.submitWin(400, for: .expert)
        XCTAssertNotNil(shared.blobs[oldID])
        let oldBlob = shared.blobs[oldID]

        // The fork applies at "next launch": no cloud writes, then a fresh
        // Scoreboard initializes over the same defaults, as the app would.
        DeviceFork.stage(in: d)
        _ = DeviceFork.applyIfPending(in: d, marker: FakeInstallMarker())
        let after = Scoreboard(defaults: d, cloud: FakeCloud(shared: shared))

        XCTAssertNotEqual(after.ownDeviceID, oldID, "new identity")
        XCTAssertEqual(shared.blobs[oldID], oldBlob, "the old blob is untouched")

        // Totals are exactly what they were — the history merged back in
        // from the old blob; only its owner changed.
        XCTAssertEqual(after.wins(for: .beginner), 2)
        XCTAssertEqual(after.wins(for: .expert), 1)
        XCTAssertEqual(after.best(for: .beginner), 250)

        // Provenance: the new install owns nothing yet; the old id reads as
        // another (ghost) device.
        let tables = after.perDeviceRecords()
        XCTAssertEqual(Set(tables.keys), [after.ownDeviceID, oldID])
        XCTAssertEqual(tables[after.ownDeviceID], [:])
        XCTAssertEqual(tables[oldID]?[GameConfig.beginner.storageKey]?.wins.mine, 2)

        // New play counts under the new identity, on top of the old totals.
        after.submitWin(200, for: .beginner)
        XCTAssertEqual(after.wins(for: .beginner), 3)
        XCTAssertEqual(after.best(for: .beginner), 200)
        XCTAssertEqual(
            after.perDeviceRecords()[after.ownDeviceID]?[GameConfig.beginner.storageKey]?
                .wins.mine, 1)
    }

    func testForkedDailyCountersDontDoubleCount() {
        let shared = CloudDailyFake.Shared()
        let d = defaults("daily")
        let id = DeviceID.current(in: d)

        let before = DailyStore(
            cloud: CloudDailyFake(shared: shared), deviceID: id, syncEnabled: true,
            defaults: d)
        before.recordAttempt(
            dateKey: "2026-07-19",
            .init(won: true, centiseconds: 1500, threeBV: 40, progress: 1, live: true))
        before.recordAttempt(
            dateKey: "2026-07-19",
            .init(won: true, centiseconds: 1400, threeBV: 40, progress: 1, live: true))
        XCTAssertEqual(before.displayRecords["2026-07-19"]?.attempts.total, 2)

        DeviceFork.stage(in: d)
        _ = DeviceFork.applyIfPending(in: d, marker: FakeInstallMarker())
        let after = DailyStore(
            cloud: CloudDailyFake(shared: shared), deviceID: DeviceID.current(in: d),
            syncEnabled: true, defaults: d)

        // The day survives via the old blob; the attempts count once, not
        // twice (the local reset is what prevents the republish).
        XCTAssertEqual(after.displayRecords["2026-07-19"]?.attempts.total, 2)
        XCTAssertEqual(after.displayRecords["2026-07-19"]?.best?.centiseconds, 1400)
    }

    // MARK: Live-clone collision (two installs, one DeviceID)

    func testCloneWritingOurSlotIsDetected() {
        let shared = FakeCloud.Shared()
        let dA = defaults("A")
        let a = Scoreboard(defaults: dA, cloud: FakeCloud(shared: shared), writerToken: "installA")
        a.submitWin(300, for: .beginner)
        XCTAssertFalse(a.idCollisionDetected, "own writes never trigger")

        // The clone: same DeviceID (defaults migrated), different install.
        let dB = defaults("B")
        dB.set(a.ownDeviceID, forKey: DeviceID.defaultsKey)
        let b = Scoreboard(defaults: dB, cloud: FakeCloud(shared: shared), writerToken: "installB")
        b.submitWin(250, for: .beginner)  // writes OUR slot → external change → A refreshes

        XCTAssertTrue(a.idCollisionDetected)
        XCTAssertTrue(b.idCollisionDetected, "A's earlier blob carries A's stamp for B too")
    }

    func testUnstampedOldBuildBlobNeverTriggers() {
        let shared = FakeCloud.Shared()
        let d = defaults("old")
        let id = DeviceID.current(in: d)
        // An old build's blob in our slot: no writer stamp.
        shared.blobs[id] = Scoreboard.encodeFile([:], epoch: 1, writer: nil)

        let board = Scoreboard(
            defaults: d, cloud: FakeCloud(shared: shared), writerToken: "installA")
        board.refreshFromCloud()
        XCTAssertFalse(board.idCollisionDetected)
    }

    func testNoTokenMeansNoDetection() {
        let shared = FakeCloud.Shared()
        let d = defaults("silent")
        let id = DeviceID.current(in: d)
        shared.blobs[id] = Scoreboard.encodeFile([:], epoch: 1, writer: "someone-else")

        let board = Scoreboard(defaults: d, cloud: FakeCloud(shared: shared))
        board.refreshFromCloud()
        XCTAssertFalse(board.idCollisionDetected, "no marker (demo/clean runs) → inert")
    }

    func testForkEndsTheCollision() {
        let shared = FakeCloud.Shared()
        let dA = defaults("A2")
        let a = Scoreboard(defaults: dA, cloud: FakeCloud(shared: shared), writerToken: "installA")
        a.submitWin(300, for: .beginner)

        let dB = defaults("B2")
        dB.set(a.ownDeviceID, forKey: DeviceID.defaultsKey)
        let b = Scoreboard(defaults: dB, cloud: FakeCloud(shared: shared), writerToken: "installB")
        b.submitWin(250, for: .beginner)
        XCTAssertTrue(a.idCollisionDetected)

        // B takes the suggested way out: fork. Its next "launch" publishes
        // under a fresh id — the shared slot is A's alone again.
        DeviceFork.stage(in: dB)
        _ = DeviceFork.applyIfPending(in: dB, marker: FakeInstallMarker())
        let b2 = Scoreboard(defaults: dB, cloud: FakeCloud(shared: shared), writerToken: "installB")
        XCTAssertNotEqual(b2.ownDeviceID, a.ownDeviceID)
        XCTAssertFalse(b2.idCollisionDetected)

        // A reclaims its slot on its next push; the household keeps counting.
        a.submitWin(280, for: .beginner)
        b2.submitWin(240, for: .beginner)
        XCTAssertEqual(b2.wins(for: .beginner), a.wins(for: .beginner))
    }
}

/// In-memory CloudDailyStore fake, mirroring FakeCloud's shape.
@MainActor
final class CloudDailyFake: CloudDailyStore {
    final class Shared {
        var blobs: [String: Data] = [:]
        var peers: [CloudDailyFake] = []
    }

    let shared: Shared
    var onExternalChange: (() -> Void)?

    init(shared: Shared) {
        self.shared = shared
        shared.peers.append(self)
    }

    var isAvailable: Bool { true }

    func writeOwnBlob(_ data: Data, deviceID: String) {
        shared.blobs[deviceID] = data
        for peer in shared.peers where peer !== self { peer.onExternalChange?() }
    }

    func deleteOwnBlob(deviceID: String) {
        shared.blobs[deviceID] = nil
        for peer in shared.peers where peer !== self { peer.onExternalChange?() }
    }

    func readAllBlobs() -> [String: Data] { shared.blobs }

    func synchronize() {}
}
