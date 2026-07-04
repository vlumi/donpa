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

    func testGroupCatalogAndMembershipPersist() throws {
        let dir = tempDir("groups")
        let p = try share()

        let store = FriendsStore(directory: dir)
        store.apply(p, now: t0)
        let work = try XCTUnwrap(store.createGroup(named: "work"))
        let family = try XCTUnwrap(store.createGroup(named: "family"))
        store.setGroups([work.id, family.id], for: p.publicKey)
        XCTAssertEqual(Set(store.friends[0].groups), [work.id, family.id])

        // A fresh store over the same dir sees the persisted catalog + membership.
        let reloaded = FriendsStore(directory: dir)
        XCTAssertEqual(Set(reloaded.groups.map(\.name)), ["work", "family"])
        XCTAssertEqual(Set(reloaded.friends.first?.groups ?? []), [work.id, family.id])
    }

    func testCreateGroupDedupesByNameAndRejectsBlank() throws {
        let store = FriendsStore.ephemeral()
        let a = try XCTUnwrap(store.createGroup(named: "  Work "))
        let b = store.createGroup(named: "work")  // case-insensitive dup → same group
        XCTAssertEqual(a.id, b?.id)
        XCTAssertEqual(store.groups.count, 1)
        XCTAssertEqual(store.groups[0].name, "Work")  // trimmed
        XCTAssertNil(store.createGroup(named: "   "))  // blank rejected
    }

    func testRenameKeepsMembershipDeleteClearsIt() throws {
        let store = FriendsStore.ephemeral()
        let p = try share()
        store.apply(p, now: t0)
        let g = try XCTUnwrap(store.createGroup(named: "old"))
        store.setGroups([g.id], for: p.publicKey)

        store.renameGroup(g.id, to: "new")  // members follow (id unchanged)
        XCTAssertEqual(store.groups[0].name, "new")
        XCTAssertEqual(store.friends[0].groups, [g.id])

        store.deleteGroup(g.id)  // vanishes from catalog AND membership
        XCTAssertTrue(store.groups.isEmpty)
        XCTAssertTrue(store.friends[0].groups.isEmpty)
    }

    func testSetGroupsDropsUnknownIDs() throws {
        let store = FriendsStore.ephemeral()
        let p = try share()
        store.apply(p, now: t0)
        let g = try XCTUnwrap(store.createGroup(named: "real"))
        store.setGroups([g.id, "bogus-id"], for: p.publicKey)
        XCTAssertEqual(store.friends[0].groups, [g.id])  // unknown dropped
    }

    /// A file written in the legacy bare-`[Friend]` format (groups were NAMES) loads
    /// by migrating: a catalog entry per distinct name, memberships rewritten to ids.
    func testMigratesLegacyNameTaggedFile() throws {
        let dir = tempDir("legacy")
        let p = try share()
        var legacy = FriendMerge.friend(from: p, existing: nil, now: t0)
        legacy.groups = ["work", "family"]  // OLD shape: names in `groups`
        let data = try JSONEncoder().encode([legacy])  // bare array, not the container
        try data.write(to: dir.appendingPathComponent("friends.json"))

        let store = FriendsStore(directory: dir)
        XCTAssertEqual(Set(store.groups.map(\.name)), ["work", "family"])
        // The friend's memberships are now ids that resolve to those names.
        let names = store.friends[0].groups.compactMap { id in
            store.groups.first { $0.id == id }?.name
        }
        XCTAssertEqual(Set(names), ["work", "family"])
    }

    private func tempDir(_ tag: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("donpa-friends-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
