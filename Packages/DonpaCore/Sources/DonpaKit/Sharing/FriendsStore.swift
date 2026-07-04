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

    public func setGroups(_ groups: [String], for publicKey: Data) {
        guard let i = friends.firstIndex(where: { $0.publicKey == publicKey }) else { return }
        friends[i].groups = groups
        save()
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
        guard let data = try? JSONEncoder().encode(friends) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
            let list = try? JSONDecoder().decode([Friend].self, from: data)
        else { return }
        friends = list
    }

    private static let appSupportDirectory: URL = {
        let fm = FileManager.default
        return
            (try? fm.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
    }()
}
