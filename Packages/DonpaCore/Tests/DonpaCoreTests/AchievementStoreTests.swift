import XCTest

@testable import DonpaCore

/// A shared-world fake of the KVS transport, mirroring ScoreboardSyncTests'.
@MainActor
final class FakeAchievementsCloud: CloudAchievementsStore {
    final class Shared {
        var blobs: [String: Data] = [:]
        var peers: [FakeAchievementsCloud] = []
    }
    let shared: Shared
    var available = true
    var onExternalChange: (() -> Void)?

    init(shared: Shared = Shared()) {
        self.shared = shared
        shared.peers.append(self)
    }
    var isAvailable: Bool { available }
    func writeOwnBlob(_ data: Data, deviceID: String) {
        guard available else { return }
        shared.blobs[deviceID] = data
        for peer in shared.peers where peer !== self { peer.onExternalChange?() }
    }
    func deleteOwnBlob(deviceID: String) { shared.blobs[deviceID] = nil }
    func readAllBlobs() -> [String: Data] { available ? shared.blobs : [:] }
    func synchronize() {}
}

/// A3: the earned store — once-only stamps, retroactive reconcile, the union
/// merge (earliest date wins), permanence, and the sync toggle.
@MainActor
final class AchievementStoreTests: XCTestCase {
    private func freshDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testRecordStampsOnceAndPersists() {
        let defaults = freshDefaults("ach.record")
        let store = AchievementStore(defaults: defaults)
        XCTAssertTrue(store.record(.winFirst, at: Date(timeIntervalSince1970: 100)))
        XCTAssertFalse(store.record(.winFirst), "a feat fires once")
        XCTAssertEqual(store.earnedTier(.winFirst), 1)
        XCTAssertEqual(store.firstEarned(.winFirst), Date(timeIntervalSince1970: 100))
        // A new store over the same defaults reads the same earnings.
        let reloaded = AchievementStore(defaults: defaults)
        XCTAssertEqual(reloaded.firstEarned(.winFirst), Date(timeIntervalSince1970: 100))
    }

    func testTieredFeatsStampPerTier() {
        let store = AchievementStore(defaults: freshDefaults("ach.tiers"))
        XCTAssertTrue(store.record(.milesWins, tier: 1))
        XCTAssertTrue(store.record(.milesWins, tier: 2))
        XCTAssertFalse(store.record(.milesWins, tier: 2))
        XCTAssertEqual(store.earnedTier(.milesWins), 2)
    }

    func testReconcileStampsOnlyTheMissing() {
        let store = AchievementStore(defaults: freshDefaults("ach.reconcile"))
        store.record(.winFirst, at: Date(timeIntervalSince1970: 5))
        let fresh = store.reconcile(
            derivable: [.winFirst: 1, .milesWins: 2],
            at: Date(timeIntervalSince1970: 50))
        XCTAssertEqual(fresh.map(\.id), [.milesWins, .milesWins])
        XCTAssertEqual(fresh.map(\.tier), [1, 2])
        // The pre-existing stamp kept its original date.
        XCTAssertEqual(store.firstEarned(.winFirst), Date(timeIntervalSince1970: 5))
        // Reconciling again is a no-op.
        XCTAssertTrue(store.reconcile(derivable: [.winFirst: 1, .milesWins: 2]).isEmpty)
    }

    func testUnionMergeTakesTheEarliestDate() {
        let shared = FakeAchievementsCloud.Shared()
        let cloudA = FakeAchievementsCloud(shared: shared)
        let cloudB = FakeAchievementsCloud(shared: shared)
        let storeA = AchievementStore(
            defaults: freshDefaults("ach.a"), cloud: cloudA, syncEnabled: true)
        let storeB = AchievementStore(
            defaults: freshDefaults("ach.b"), cloud: cloudB, syncEnabled: true)
        storeA.record(.lunaticWin, at: Date(timeIntervalSince1970: 200))
        // B earned the same feat EARLIER (offline device that synced late).
        storeB.record(.lunaticWin, at: Date(timeIntervalSince1970: 100))
        // Both converge on the earliest date.
        XCTAssertEqual(storeA.firstEarned(.lunaticWin), Date(timeIntervalSince1970: 100))
        XCTAssertEqual(storeB.firstEarned(.lunaticWin), Date(timeIntervalSince1970: 100))
        // And the union carries feats across devices.
        storeA.record(.hiveFirst, at: Date(timeIntervalSince1970: 300))
        XCTAssertEqual(storeB.earnedTier(.hiveFirst), 1)
    }

    func testSyncOffRemovesTheSlotButKeepsLocal() {
        let shared = FakeAchievementsCloud.Shared()
        let cloud = FakeAchievementsCloud(shared: shared)
        let store = AchievementStore(
            defaults: freshDefaults("ach.off"), cloud: cloud, syncEnabled: true)
        store.record(.winFirst)
        XCTAssertEqual(shared.blobs.count, 1)
        store.setSyncEnabled(false)
        XCTAssertTrue(shared.blobs.isEmpty, "own slot removed")
        XCTAssertEqual(store.earnedTier(.winFirst), 1, "permanence: local earnings stay")
    }

    func testEnablingSyncLaterPublishesAndMerges() {
        let shared = FakeAchievementsCloud.Shared()
        let cloudA = FakeAchievementsCloud(shared: shared)
        let cloudB = FakeAchievementsCloud(shared: shared)
        let storeA = AchievementStore(
            defaults: freshDefaults("ach.late.a"), cloud: cloudA, syncEnabled: true)
        storeA.record(.hiveFirst, at: Date(timeIntervalSince1970: 10))
        // B lived offline-by-choice, earning locally…
        let storeB = AchievementStore(
            defaults: freshDefaults("ach.late.b"), cloud: cloudB, syncEnabled: false)
        storeB.record(.winFirst, at: Date(timeIntervalSince1970: 20))
        XCTAssertEqual(shared.blobs.count, 1, "sync-off never publishes")
        // …then flips the toggle: its earnings publish AND the cloud's merge in.
        storeB.setSyncEnabled(true)
        XCTAssertEqual(shared.blobs.count, 2)
        XCTAssertEqual(storeB.earnedTier(.hiveFirst), 1)
        XCTAssertEqual(storeA.earnedTier(.winFirst), 1)
    }

    func testUnavailableCloudIsALocalStore() {
        let cloud = FakeAchievementsCloud()
        cloud.available = false
        let store = AchievementStore(
            defaults: freshDefaults("ach.offline"), cloud: cloud, syncEnabled: true)
        store.record(.winFirst)
        XCTAssertTrue(cloud.shared.blobs.isEmpty)
        XCTAssertEqual(store.earnedTier(.winFirst), 1)
    }

    func testUnknownIDsAreDroppedFromDecodeNotCrashed() {
        let defaults = freshDefaults("ach.unknown")
        let wire = #"{"version":1,"earned":{"future.feat":{"1":0},"win.first":{"1":0}}}"#
        defaults.set(Data(wire.utf8), forKey: "donpa.achievements.v1")
        let store = AchievementStore(defaults: defaults)
        XCTAssertEqual(store.earnedTier(.winFirst), 1)
        XCTAssertEqual(store.earned.count, 1)
    }
}
