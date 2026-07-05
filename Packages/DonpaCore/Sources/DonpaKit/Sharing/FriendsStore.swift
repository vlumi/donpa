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
    /// The LIVE friends — tombstones filtered out. What the UI shows.
    @Published public private(set) var friends: [Friend] = []
    /// The LIVE group catalog (id + name), tombstones filtered out. Groups exist
    /// independently of membership, so an empty group persists. `Friend.groups` holds
    /// ids into this.
    @Published public private(set) var groups: [FriendGroup] = []

    /// The full backing sets INCLUDING soft-delete tombstones — persisted and synced,
    /// so a delete propagates across devices and can't resurrect. The published
    /// `friends`/`groups` are the live projections of these.
    private var allFriends: [Friend] = []
    private var allGroups: [FriendGroup] = []

    private let url: URL
    private let cloud: (any CloudFriendsStore)?
    private let deviceID: String

    /// User gate — mirrors the scoreboard's `syncScores`. Off → this device's blob is
    /// removed and only local records show; on → push + merge.
    public var syncEnabled: Bool {
        didSet {
            guard syncEnabled != oldValue else { return }
            if syncEnabled {
                pushAndMerge()
            } else {
                cloud?.deleteOwnBlob(deviceID: deviceID)
                rebuildFromOwn()  // drop others' contributions from the live view
            }
        }
    }

    public init(
        directory: URL? = nil, filename: String = "friends.json",
        cloud: (any CloudFriendsStore)? = nil,
        deviceID: String = "local", syncEnabled: Bool = false
    ) {
        let dir = directory ?? Self.appSupportDirectory
        self.url = dir.appendingPathComponent(filename)
        self.cloud = cloud
        self.deviceID = deviceID
        self.syncEnabled = syncEnabled
        load()
        cloud?.onExternalChange = { [weak self] in self?.pushAndMerge() }
        if syncEnabled { pushAndMerge() }
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
        // Classify against LIVE friends only — a tombstoned friend re-adds cleanly.
        let outcome = FriendMerge.outcome(for: payload, existing: friends)
        switch outcome {
        case .add:
            put(stamped(FriendMerge.friend(from: payload, existing: nil, now: now), now))
        case .refresh:
            put(
                stamped(
                    FriendMerge.friend(
                        from: payload, existing: liveFriend(payload.publicKey), now: now), now))
        case .migrate(let oldKey):
            // Re-key: tombstone the old identity, add the new preserving your locals.
            let existing = liveFriend(oldKey)
            tombstoneFriend(oldKey, now: now)
            put(stamped(FriendMerge.friend(from: payload, existing: existing, now: now), now))
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
        put(stamped(f, now))
    }

    /// Replace an existing friend's identity+data with the payload's (the "replace"
    /// resolution for a collision): tombstone the clashing one, add the new.
    public func replaceOnCollision(
        _ payload: SharePayload, replacing oldKey: Data, now: Date = Date()
    ) {
        let keep = liveFriend(oldKey)
        tombstoneFriend(oldKey, now: now)
        put(stamped(FriendMerge.friend(from: payload, existing: keep, now: now), now))
    }

    // MARK: List management

    public func delete(_ publicKey: Data, now: Date = Date()) {
        tombstoneFriend(publicKey, now: now)
    }

    public func setAlias(_ alias: String?, for publicKey: Data, now: Date = Date()) {
        guard var f = liveFriend(publicKey) else { return }
        let trimmed = alias?.trimmingCharacters(in: .whitespacesAndNewlines)
        f.localAlias = (trimmed?.isEmpty ?? true) ? nil : trimmed
        put(stamped(f, now))
    }

    /// Set a friend's group memberships (a set of `FriendGroup` ids). Ids not in the
    /// LIVE catalog are dropped — membership can't reference a missing group.
    public func setGroups(_ groupIDs: [String], for publicKey: Data, now: Date = Date()) {
        guard var f = liveFriend(publicKey) else { return }
        let known = Set(groups.map(\.id))
        f.groups = groupIDs.filter(known.contains)
        put(stamped(f, now))
    }

    // MARK: Group catalog

    /// Create a group with a trimmed name, or return the existing LIVE one if a group
    /// by that name (case-insensitive) already exists — so "create" from a picker never
    /// makes accidental duplicates. Returns nil if the name is blank.
    @discardableResult
    public func createGroup(named name: String, now: Date = Date()) -> FriendGroup? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = groups.first(where: {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return existing
        }
        let group = FriendGroup(name: trimmed, updatedAt: now)
        putGroup(group)
        return group
    }

    /// Rename a group (members follow, since they reference the id). No-op on a blank
    /// name or an unknown live id.
    public func renameGroup(_ id: String, to name: String, now: Date = Date()) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var g = groups.first(where: { $0.id == id }) else { return }
        g.name = trimmed
        g.updatedAt = now
        putGroup(g)
    }

    /// Delete a group (tombstone it) and drop its id from every friend's membership.
    public func deleteGroup(_ id: String, now: Date = Date()) {
        guard let g = allGroups.first(where: { $0.id == id }) else { return }
        putGroup(g.tombstone(now: now))
        for f in allFriends where !f.isDeleted && f.groups.contains(id) {
            var updated = f
            updated.groups.removeAll { $0 == id }
            put(stamped(updated, now))
        }
    }

    /// Toggle a friend's membership in a group (convenience for the picker).
    public func setMembership(
        _ member: Bool, of publicKey: Data, in groupID: String, now: Date = Date()
    ) {
        guard groups.contains(where: { $0.id == groupID }), var f = liveFriend(publicKey) else {
            return
        }
        if member {
            if !f.groups.contains(groupID) { f.groups.append(groupID) }
        } else {
            f.groups.removeAll { $0 == groupID }
        }
        put(stamped(f, now))
    }

    /// The live friends who belong to a group (by id). Order preserved from `friends`.
    public func members(of groupID: String) -> [Friend] {
        friends.filter { $0.groups.contains(groupID) }
    }

    // MARK: Internals

    /// The live (non-tombstoned) friend for a key, if any.
    private func liveFriend(_ key: Data) -> Friend? {
        friends.first { $0.publicKey == key }
    }

    /// Bump `updatedAt` so this edit wins the cross-device merge.
    private func stamped(_ friend: Friend, _ now: Date) -> Friend {
        var f = friend
        f.updatedAt = now
        return f
    }

    /// Upsert a friend into the backing set (by public key), then republish + persist.
    private func put(_ friend: Friend) {
        if let i = allFriends.firstIndex(where: { $0.publicKey == friend.publicKey }) {
            allFriends[i] = friend
        } else {
            allFriends.append(friend)
        }
        commit()
    }

    /// Replace a friend with its minimal tombstone (or no-op if unknown/already gone).
    private func tombstoneFriend(_ key: Data, now: Date) {
        guard let i = allFriends.firstIndex(where: { $0.publicKey == key }),
            !allFriends[i].isDeleted
        else { return }
        allFriends[i] = allFriends[i].tombstone(now: now)
        commit()
    }

    private func putGroup(_ group: FriendGroup) {
        if let i = allGroups.firstIndex(where: { $0.id == group.id }) {
            allGroups[i] = group
        } else {
            allGroups.append(group)
        }
        commit()
    }

    /// Recompute the published live view, persist this device's own set, and (when
    /// syncing) push the own blob so other devices see the change. The published view
    /// is the merge of THIS device's records with every other device's blob; the
    /// backing `allFriends`/`allGroups` remain this device's own records only, so we
    /// never re-publish others' records as our own.
    private func commit() {
        save()
        if syncEnabled, let cloud, cloud.isAvailable {
            if let data = try? JSONEncoder().encode(
                FriendsStored(friends: allFriends, groups: allGroups))
            {
                cloud.writeOwnBlob(data, deviceID: deviceID)
            }
            republishMerged()
        } else {
            rebuildFromOwn()
        }
    }

    /// Publish own-only (tombstones filtered) — when sync is off or iCloud is away.
    private func rebuildFromOwn() {
        friends = FriendSyncMerge.live(allFriends)
        groups = sortedLive(allGroups)
    }

    /// Publish the merge of this device's records with every other device's blob.
    private func republishMerged() {
        let others = otherBlobs()
        let mergedFriends = FriendSyncMerge.mergeFriends([allFriends] + others.map(\.friends))
        let mergedGroups = FriendSyncMerge.mergeGroups([allGroups] + others.map(\.groups))
        friends = FriendSyncMerge.live(mergedFriends)
        groups = sortedLive(mergedGroups)
    }

    /// Live groups (tombstones filtered) in a STABLE alphabetical order — the merge
    /// yields dictionary order, which is otherwise arbitrary and shifts across launches.
    private func sortedLive(_ groups: [FriendGroup]) -> [FriendGroup] {
        FriendSyncMerge.live(groups).sorted {
            let byName = $0.name.localizedCaseInsensitiveCompare($1.name)
            return byName != .orderedSame ? byName == .orderedAscending : $0.id < $1.id
        }
    }

    /// Decode every OTHER device's blob (skip our own slot; own records come from
    /// `allFriends`, already current in memory).
    private func otherBlobs() -> [FriendsStored] {
        guard let cloud, cloud.isAvailable else { return [] }
        let decoder = JSONDecoder()
        return cloud.readAllBlobs()
            .filter { $0.key != deviceID }
            .values
            .compactMap { try? decoder.decode(FriendsStored.self, from: $0) }
    }

    /// Re-pull + merge from the cloud now (e.g. before showing the friends list).
    /// No-op when sync is off. Exposed so the UI (and tests) can force a refresh.
    public func refreshFromCloud() { pushAndMerge() }

    /// Pull others' records into this device's OWN set (a genuine union that persists),
    /// then re-publish. Used on enabling sync / external change: adopting another
    /// device's friends means they become ours too, so a later sync-off keeps them.
    private func pushAndMerge() {
        guard syncEnabled, let cloud, cloud.isAvailable else {
            rebuildFromOwn()
            return
        }
        let others = otherBlobs()
        allFriends = FriendSyncMerge.mergeFriends([allFriends] + others.map(\.friends))
        allGroups = FriendSyncMerge.mergeGroups([allGroups] + others.map(\.groups))
        save()
        if let data = try? JSONEncoder().encode(
            FriendsStored(friends: allFriends, groups: allGroups))
        {
            cloud.writeOwnBlob(data, deviceID: deviceID)
        }
        rebuildFromOwn()  // own set is now the union, so own-only == merged
    }

    private func save() {
        let stored = FriendsStored(friends: allFriends, groups: allGroups)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        // Current format: a { friends, groups } container (may hold tombstones).
        if let stored = try? decoder.decode(FriendsStored.self, from: data) {
            allFriends = stored.friends
            allGroups = stored.groups
            friends = FriendSyncMerge.live(allFriends)
            groups = sortedLive(allGroups)
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
        allFriends = legacy
        allGroups = catalog
        commit()
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
