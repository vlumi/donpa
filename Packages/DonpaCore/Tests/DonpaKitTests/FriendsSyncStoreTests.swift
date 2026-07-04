import DonpaCore
import XCTest

@testable import DonpaKit

/// End-to-end friend-list sync through the store: two devices sharing one in-memory
/// cloud, exercising push → merge → tombstone propagation → union, via the real
/// `FriendsStore` (not just the pure merge).
@MainActor
final class FriendsSyncStoreTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// An in-memory `CloudFriendsStore` shared by the test's "devices".
    private final class MockCloud: CloudFriendsStore {
        var blobs: [String: Data] = [:]
        var isAvailable = true
        var onExternalChange: (() -> Void)?
        func writeOwnBlob(_ data: Data, deviceID: String) { blobs[deviceID] = data }
        func deleteOwnBlob(deviceID: String) { blobs[deviceID] = nil }
        func readAllBlobs() -> [String: Data] { blobs }
        func synchronize() {}
    }

    private func device(_ id: String, _ cloud: MockCloud, dir: URL) -> FriendsStore {
        FriendsStore(directory: dir, cloud: cloud, deviceID: id, syncEnabled: true)
    }

    private func tempDir(_ tag: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("donpa-sync-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func share(_ id: ShareIdentity, name: String, at: Date) throws -> SharePayload {
        try id.makePayload(
            name: name,
            scores: [
                SharedConfigScore(key: "v2|basic|beginner", best: 5, wins: 1, bestProgress: nil)
            ],
            career: nil, issuedAt: at)
    }

    func testAddOnOneDevicePropagatesToOther() throws {
        let cloud = MockCloud()
        let a = device("A", cloud, dir: tempDir("a"))
        a.apply(try share(ShareIdentity(), name: "Ville", at: t0), now: t0)

        // A second device syncing the same cloud sees Ville after its initial merge.
        let b = device("B", cloud, dir: tempDir("b"))
        XCTAssertEqual(b.friends.map(\.sharedName), ["Ville"])
    }

    func testDeleteOnOneDevicePropagates() throws {
        let cloud = MockCloud()
        let dirA = tempDir("a")
        let a = device("A", cloud, dir: dirA)
        let p = try share(ShareIdentity(), name: "Ville", at: t0)
        a.apply(p, now: t0)

        // B syncs, sees Ville, then A deletes and B re-syncs (external change).
        let b = device("B", cloud, dir: tempDir("b"))
        XCTAssertEqual(b.friends.count, 1)
        a.delete(p.publicKey, now: t0.addingTimeInterval(60))
        b.refreshFromCloud()
        XCTAssertTrue(b.friends.isEmpty)  // delete propagated
    }

    func testFirstMergeUnionsBothDevices() throws {
        let cloud = MockCloud()
        // A and B each pinned a DIFFERENT friend while independent (own blobs).
        let a = device("A", cloud, dir: tempDir("a"))
        a.apply(try share(ShareIdentity(), name: "Alice", at: t0), now: t0)
        let b = device("B", cloud, dir: tempDir("b"))
        b.apply(try share(ShareIdentity(), name: "Bob", at: t0), now: t0)

        // A re-merges: it should now see BOTH (union, nobody dropped).
        a.refreshFromCloud()
        XCTAssertEqual(Set(a.friends.map(\.sharedName)), ["Alice", "Bob"])
    }

    func testGroupCreatedOnOneDevicePropagates() throws {
        let cloud = MockCloud()
        let a = device("A", cloud, dir: tempDir("a"))
        a.createGroup(named: "work", now: t0)

        let b = device("B", cloud, dir: tempDir("b"))
        XCTAssertEqual(b.groups.map(\.name), ["work"])
    }

    func testSyncOffKeepsUnionedFriendsLocally() throws {
        let cloud = MockCloud()
        let a = device("A", cloud, dir: tempDir("a"))
        a.apply(try share(ShareIdentity(), name: "Alice", at: t0), now: t0)
        let bDir = tempDir("b")
        let b = device("B", cloud, dir: bDir)  // adopts Alice via union on init
        XCTAssertEqual(b.friends.map(\.sharedName), ["Alice"])

        b.syncEnabled = false  // going offline shouldn't drop the adopted friend
        XCTAssertEqual(b.friends.map(\.sharedName), ["Alice"])
        // …and it persists locally.
        let reloaded = FriendsStore(
            directory: bDir, cloud: cloud, deviceID: "B", syncEnabled: false)
        XCTAssertEqual(reloaded.friends.map(\.sharedName), ["Alice"])
    }
}
