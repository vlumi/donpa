import XCTest

@testable import DonpaCore

/// The pure cross-device friend/group merge: last-writer-wins per key, soft-delete
/// tombstones that propagate and don't resurrect, and union across devices.
final class FriendSyncMergeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func friend(_ key: UInt8, name: String, updated: Date, deleted: Date? = nil) -> Friend {
        Friend(
            publicKey: Data([key]), sharedName: name, lastIssuedAt: t0,
            scores: [], career: nil, addedAt: t0, updatedAt: updated, deletedAt: deleted)
    }

    func testUnionAcrossDevices() {
        let a = friend(1, name: "A", updated: t0)
        let b = friend(2, name: "B", updated: t0)
        let merged = FriendSyncMerge.mergeFriends([[a], [b]])
        XCTAssertEqual(Set(FriendSyncMerge.live(merged).map(\.sharedName)), ["A", "B"])
    }

    func testNewerEditWins() {
        let old = friend(1, name: "old", updated: t0)
        let new = friend(1, name: "new", updated: t0.addingTimeInterval(60))
        // Order-independent: newest updatedAt wins either way.
        for blobs in [[[old], [new]], [[new], [old]]] {
            let merged = FriendSyncMerge.mergeFriends(blobs)
            XCTAssertEqual(merged.count, 1)
            XCTAssertEqual(merged[0].sharedName, "new")
        }
    }

    func testTombstoneWinsAndHidesFromLive() {
        let live = friend(1, name: "A", updated: t0)
        let dead = friend(
            1, name: "", updated: t0.addingTimeInterval(60), deleted: t0.addingTimeInterval(60))
        let merged = FriendSyncMerge.mergeFriends([[live], [dead]])
        XCTAssertEqual(merged.count, 1)  // tombstone retained (so delete keeps propagating)
        XCTAssertTrue(merged[0].isDeleted)
        XCTAssertTrue(FriendSyncMerge.live(merged).isEmpty)  // hidden from the display list
    }

    func testDeleteDoesNotResurrectFromStaleDevice() {
        // Device A deleted the friend (later); device B still has the old live copy.
        let staleLive = friend(1, name: "A", updated: t0)
        let tombstone = friend(
            1, name: "", updated: t0.addingTimeInterval(60), deleted: t0.addingTimeInterval(60))
        let merged = FriendSyncMerge.mergeFriends([[tombstone], [staleLive]])
        XCTAssertTrue(FriendSyncMerge.live(merged).isEmpty)  // stays deleted
    }

    func testReAddAfterDeleteWins() {
        // A later re-add (newer than the tombstone) brings the friend back.
        let tombstone = friend(
            1, name: "", updated: t0.addingTimeInterval(60), deleted: t0.addingTimeInterval(60))
        let readd = friend(1, name: "A again", updated: t0.addingTimeInterval(120))
        let merged = FriendSyncMerge.mergeFriends([[tombstone], [readd]])
        XCTAssertEqual(FriendSyncMerge.live(merged).map(\.sharedName), ["A again"])
    }

    func testEqualTimestampsPreferTombstoneDeterministically() {
        let live = friend(1, name: "A", updated: t0)
        let dead = friend(1, name: "", updated: t0, deleted: t0)  // same instant
        // Whichever order, the delete wins the tie — devices converge.
        XCTAssertTrue(FriendSyncMerge.mergeFriends([[live], [dead]])[0].isDeleted)
        XCTAssertTrue(FriendSyncMerge.mergeFriends([[dead], [live]])[0].isDeleted)
    }

    func testGroupMergeByIDAndTombstone() {
        let g = FriendGroup(id: "x", name: "work", updatedAt: t0)
        let renamed = FriendGroup(id: "x", name: "office", updatedAt: t0.addingTimeInterval(60))
        let merged = FriendSyncMerge.mergeGroups([[g], [renamed]])
        XCTAssertEqual(FriendSyncMerge.live(merged).map(\.name), ["office"])

        let dead = FriendGroup(
            id: "x", name: "", updatedAt: t0.addingTimeInterval(120),
            deletedAt: t0.addingTimeInterval(120))
        XCTAssertTrue(
            FriendSyncMerge.live(FriendSyncMerge.mergeGroups([[renamed], [dead]])).isEmpty)
    }
}
