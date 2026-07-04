import Foundation

/// The pure, deterministic merge for cross-device friend-list sync.
///
/// Unlike the scoreboard (cumulative G-counters), the friend list is a mutable SET
/// with per-record edits, so the merge is **last-writer-wins per record with
/// soft-delete tombstones**:
///
/// - Each device writes one blob holding ITS view of every friend + group, each
///   record carrying `updatedAt` (and `deletedAt` if removed).
/// - Merging picks, per key (friend = public key, group = id), the record with the
///   newest `updatedAt` across all blobs — including this device's own.
/// - A winning record with `deletedAt` set is a **tombstone**: kept in the merged
///   set (so the delete keeps propagating) but filtered out of the live list.
///
/// Pure (no I/O, no clock) so it's unit-testable headless. Ties on `updatedAt` break
/// deterministically toward the deleted / lexicographically-greater version, so all
/// devices converge regardless of read order.
public enum FriendSyncMerge {
    /// Merge this device's friends with every device's blobs (own included is fine;
    /// duplicates are idempotent). Returns ALL records incl. tombstones — call
    /// `live(_:)` for the display list.
    public static func mergeFriends(_ blobs: [[Friend]]) -> [Friend] {
        var winner: [Data: Friend] = [:]
        for blob in blobs {
            for friend in blob {
                if let current = winner[friend.publicKey] {
                    winner[friend.publicKey] = pickFriend(current, friend)
                } else {
                    winner[friend.publicKey] = friend
                }
            }
        }
        return Array(winner.values)
    }

    /// Merge group catalogs the same way, keyed by id.
    public static func mergeGroups(_ blobs: [[FriendGroup]]) -> [FriendGroup] {
        var winner: [String: FriendGroup] = [:]
        for blob in blobs {
            for group in blob {
                if let current = winner[group.id] {
                    winner[group.id] = pickGroup(current, group)
                } else {
                    winner[group.id] = group
                }
            }
        }
        return Array(winner.values)
    }

    /// The live (non-tombstoned) friends from a merged set.
    public static func live(_ friends: [Friend]) -> [Friend] { friends.filter { !$0.isDeleted } }

    /// The live (non-tombstoned) groups from a merged set.
    public static func live(_ groups: [FriendGroup]) -> [FriendGroup] {
        groups.filter { !$0.isDeleted }
    }

    // MARK: Per-record winners

    private static func pickFriend(_ a: Friend, _ b: Friend) -> Friend {
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt ? a : b }
        // Equal timestamps: prefer a tombstone (a delete shouldn't lose to a stale
        // edit at the same instant), then a stable field so devices agree.
        if a.isDeleted != b.isDeleted { return a.isDeleted ? a : b }
        return a.displayName >= b.displayName ? a : b
    }

    private static func pickGroup(_ a: FriendGroup, _ b: FriendGroup) -> FriendGroup {
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt ? a : b }
        if a.isDeleted != b.isDeleted { return a.isDeleted ? a : b }
        return a.name >= b.name ? a : b
    }
}
