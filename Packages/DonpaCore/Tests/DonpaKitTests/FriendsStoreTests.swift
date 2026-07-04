import DonpaCore
import XCTest

@testable import DonpaKit

/// FriendsStore: applying verified shares per the TOFU outcome, collision
/// resolution, and list management — on an ephemeral store, with persistence.
@MainActor
final class FriendsStoreTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func share(
        _ id: ShareIdentity = ShareIdentity(), name: String = "Ville", at: Date? = nil
    ) throws -> SharePayload {
        try id.makePayload(
            name: name,
            scores: [
                SharedConfigScore(key: "v2|basic|beginner", best: 500, wins: 1, bestProgress: nil)
            ],
            career: nil, issuedAt: at ?? t0)
    }

    func testAddThenRefreshInPlace() throws {
        let store = FriendsStore.ephemeral()
        let id = ShareIdentity()
        XCTAssertEqual(store.apply(try share(id, at: t0), now: t0), .add)
        XCTAssertEqual(store.friends.count, 1)
        // A newer share from the same identity refreshes, not duplicates.
        let newer = try share(id, name: "Ville!", at: t0.addingTimeInterval(60))
        XCTAssertEqual(store.apply(newer, now: t0), .refresh)
        XCTAssertEqual(store.friends.count, 1)
        XCTAssertEqual(store.friends[0].sharedName, "Ville!")
    }

    func testStaleShareIgnored() throws {
        let store = FriendsStore.ephemeral()
        let id = ShareIdentity()
        store.apply(try share(id, at: t0.addingTimeInterval(60)), now: t0)
        XCTAssertEqual(store.apply(try share(id, at: t0), now: t0), .stale)
        XCTAssertEqual(store.friends[0].sharedName, "Ville")  // unchanged
    }

    func testCollisionNotAppliedUntilResolved() throws {
        let store = FriendsStore.ephemeral()
        store.apply(try share(ShareIdentity(), name: "Ville"), now: t0)
        let clash = try share(ShareIdentity(), name: "Ville")  // same name, new key
        if case .nameCollision = store.apply(clash, now: t0) {
            XCTAssertEqual(store.friends.count, 1)  // not added yet
            store.addResolvingCollision(clash, alias: "Ville (work)", now: t0)
            XCTAssertEqual(store.friends.count, 2)
            XCTAssertTrue(store.friends.contains { $0.localAlias == "Ville (work)" })
        } else {
            XCTFail("expected a name collision")
        }
    }

    func testAliasAndDeletePersist() throws {
        let store = FriendsStore.ephemeral()
        let p = try share()
        store.apply(p, now: t0)
        store.setAlias("Bro", for: p.publicKey)
        XCTAssertEqual(store.friends[0].displayName, "Bro")
        store.setAlias("   ", for: p.publicKey)  // blanking clears it
        XCTAssertNil(store.friends[0].localAlias)
        store.delete(p.publicKey)
        XCTAssertTrue(store.friends.isEmpty)
    }

    func testGroupsPersistAndReload() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("donpa-friends-groups-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let p = try share()

        let store = FriendsStore(directory: dir)
        store.apply(p, now: t0)
        store.setGroups(["work", "family"], for: p.publicKey)
        XCTAssertEqual(store.friends[0].groups, ["work", "family"])

        // A fresh store over the same dir sees the persisted groups (atomic write).
        let reloaded = FriendsStore(directory: dir)
        XCTAssertEqual(reloaded.friends.first?.groups, ["work", "family"])
    }
}
