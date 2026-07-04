import Combine
import DonpaCore
import Foundation

/// Persists the tracked-friends list and applies verified shares to it. An
/// `ObservableObject` so the friends list / comparison UI react to changes.
///
/// Holds ONLY friend data — never your own stats (the display-merge invariant:
/// deleting a friend makes their rows vanish with nothing to clean). Atomic writes,
/// tolerant loads, mirroring `SaveStore`.
@MainActor
public final class FriendsStore: ObservableObject {
    @Published public private(set) var friends: [Friend] = []
    /// The group catalog (id + name). Groups exist independently of membership, so an
    /// empty group persists. `Friend.groups` holds ids into this.
    @Published public private(set) var groups: [FriendGroup] = []

    private let url: URL

    public init(directory: URL? = nil, filename: String = "friends.json") {
        let dir = directory ?? Self.appSupportDirectory
        self.url = dir.appendingPathComponent(filename)
        load()
    }

    /// A throwaway store in a unique temp dir — for UI tests / previews.
    public static func ephemeral() -> FriendsStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("donpa-friends-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return FriendsStore(directory: dir)
    }

    // MARK: Applying a received share

    /// Apply a verified payload per its `FriendMerge.Outcome`. Returns the outcome so
    /// the receive UI can react (silent add/refresh/migrate vs. a collision that
    /// needs a prompt — a `.nameCollision` is NOT applied here; the UI resolves it,
    /// then calls `add(resolving:)`). `now` injected for testability.
    @discardableResult
    public func apply(_ payload: SharePayload, now: Date = Date()) -> FriendMerge.Outcome {
        let outcome = FriendMerge.outcome(for: payload, existing: friends)
        switch outcome {
        case .add:
            friends.append(FriendMerge.friend(from: payload, existing: nil, now: now))
            save()
        case .refresh:
            upsert(
                FriendMerge.friend(from: payload, existing: existing(payload.publicKey), now: now))
        case .migrate(let oldKey):
            // Re-key the existing friend to the new identity, preserving your locals.
            let existing = existing(oldKey)
            friends.removeAll { $0.publicKey == oldKey }
            friends.append(FriendMerge.friend(from: payload, existing: existing, now: now))
            save()
        case .stale, .nameCollision:
            break  // stale: ignore; collision: UI prompts, then resolveCollision(...)
        }
        return outcome
    }

    /// Force-add a payload as a NEW friend despite a name collision (the "keep both"
    /// resolution). Optionally set a disambiguating alias.
    public func addResolvingCollision(_ payload: SharePayload, alias: String?, now: Date = Date()) {
        var f = FriendMerge.friend(from: payload, existing: nil, now: now)
        f.localAlias = alias
        friends.append(f)
        save()
    }

    /// Replace an existing friend's identity+data with the payload's (the "replace"
    /// resolution for a collision): drop the clashing one, add the new.
    public func replaceOnCollision(
        _ payload: SharePayload, replacing oldKey: Data, now: Date = Date()
    ) {
        let keep = existing(oldKey)
        friends.removeAll { $0.publicKey == oldKey }
        friends.append(FriendMerge.friend(from: payload, existing: keep, now: now))
        save()
    }

    // MARK: List management

    public func delete(_ publicKey: Data) {
        friends.removeAll { $0.publicKey == publicKey }
        save()
    }

    public func setAlias(_ alias: String?, for publicKey: Data) {
        guard let i = friends.firstIndex(where: { $0.publicKey == publicKey }) else { return }
        let trimmed = alias?.trimmingCharacters(in: .whitespacesAndNewlines)
        friends[i].localAlias = (trimmed?.isEmpty ?? true) ? nil : trimmed
        save()
    }

    /// Set a friend's group memberships (a set of `FriendGroup` ids). Ids not in the
    /// catalog are dropped — membership can't reference a group that doesn't exist.
    public func setGroups(_ groupIDs: [String], for publicKey: Data) {
        guard let i = friends.firstIndex(where: { $0.publicKey == publicKey }) else { return }
        let known = Set(groups.map(\.id))
        friends[i].groups = groupIDs.filter(known.contains)
        save()
    }

    // MARK: Group catalog

    /// Create a group with a trimmed name, or return the existing one if a group by
    /// that name (case-insensitive) already exists — so "create" from a picker never
    /// makes accidental duplicates. Returns nil if the name is blank.
    @discardableResult
    public func createGroup(named name: String) -> FriendGroup? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = groups.first(where: {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return existing
        }
        let group = FriendGroup(name: trimmed)
        groups.append(group)
        save()
        return group
    }

    /// Rename a group (members follow, since they reference the id). No-op on a blank
    /// name or an unknown id.
    public func renameGroup(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[i].name = trimmed
        save()
    }

    /// Delete a group and remove its id from every friend's membership.
    public func deleteGroup(_ id: String) {
        groups.removeAll { $0.id == id }
        for i in friends.indices {
            friends[i].groups.removeAll { $0 == id }
        }
        save()
    }

    /// Toggle a friend's membership in a group (convenience for the picker).
    public func setMembership(_ member: Bool, of publicKey: Data, in groupID: String) {
        guard groups.contains(where: { $0.id == groupID }),
            let i = friends.firstIndex(where: { $0.publicKey == publicKey })
        else { return }
        var set = friends[i].groups
        if member {
            if !set.contains(groupID) { set.append(groupID) }
        } else {
            set.removeAll { $0 == groupID }
        }
        friends[i].groups = set
        save()
    }

    /// The friends who belong to a group (by id). Order preserved from `friends`.
    public func members(of groupID: String) -> [Friend] {
        friends.filter { $0.groups.contains(groupID) }
    }

    // MARK: Internals

    private func existing(_ key: Data) -> Friend? { friends.first { $0.publicKey == key } }

    private func upsert(_ friend: Friend) {
        if let i = friends.firstIndex(where: { $0.publicKey == friend.publicKey }) {
            friends[i] = friend
        } else {
            friends.append(friend)
        }
        save()
    }

    private func save() {
        let stored = FriendsStored(friends: friends, groups: groups)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        // Current format: a { friends, groups } container.
        if let stored = try? decoder.decode(FriendsStored.self, from: data) {
            friends = stored.friends
            groups = stored.groups
            return
        }
        // Legacy format: a bare [Friend] whose `groups` held NAMES, not ids. Migrate:
        // mint a catalog entry per distinct name and rewrite memberships to ids.
        if var legacy = try? decoder.decode([Friend].self, from: data) {
            migrate(legacy: &legacy)
        }
    }

    /// Turn name-tag memberships into an id-based catalog in place, then persist the
    /// migrated form so the next load takes the fast path.
    private func migrate(legacy: inout [Friend]) {
        var idByName: [String: String] = [:]
        var catalog: [FriendGroup] = []
        for friend in legacy {
            for name in friend.groups where idByName[name] == nil {
                let group = FriendGroup(name: name)
                idByName[name] = group.id
                catalog.append(group)
            }
        }
        for i in legacy.indices {
            legacy[i].groups = legacy[i].groups.compactMap { idByName[$0] }
        }
        friends = legacy
        groups = catalog
        save()
    }

    private static let appSupportDirectory: URL = {
        let fm = FileManager.default
        return
            (try? fm.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
    }()
}

/// The on-disk shape for `FriendsStore`: friends plus the group catalog. Tolerant
/// decode so a file written by a newer/older build (missing `groups`) still loads;
/// `friends` is required, so a legacy bare-`[Friend]` file fails here and `load()`
/// falls through to its migration path. File-scoped (not nested) to satisfy the
/// nesting limit.
private struct FriendsStored: Codable {
    var friends: [Friend]
    var groups: [FriendGroup]

    init(friends: [Friend], groups: [FriendGroup]) {
        self.friends = friends
        self.groups = groups
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        friends = try c.decode([Friend].self, forKey: .friends)
        groups = try c.decodeIfPresent([FriendGroup].self, forKey: .groups) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case friends = "f", groups = "g"
    }
}
