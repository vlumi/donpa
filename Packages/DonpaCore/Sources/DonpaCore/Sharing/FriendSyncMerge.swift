import Foundation

/// Pure, deterministic merge for cross-device friend-list sync: last-writer-wins per
/// record (by `updatedAt`; friend keyed by public key, group by id) with soft-delete
/// tombstones. A winning tombstone stays in the merged set so the delete keeps
/// propagating, but is filtered from the live list. Ties break deterministically
/// (tombstone first, then a stable field) so all devices converge regardless of
/// read order.
public enum FriendSyncMerge {
    /// Merges every device's blobs (own included; duplicates are idempotent). Returns
    /// ALL records incl. tombstones — call `live(_:)` for the display list.
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

    /// Same merge for group catalogs, keyed by id.
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

    public static func live(_ friends: [Friend]) -> [Friend] { friends.filter { !$0.isDeleted } }

    public static func live(_ groups: [FriendGroup]) -> [FriendGroup] {
        groups.filter { !$0.isDeleted }
    }

    private static func pickFriend(_ a: Friend, _ b: Friend) -> Friend {
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt ? a : b }
        // Equal timestamps: a delete must not lose to a stale edit; then a stable
        // field so devices agree.
        if a.isDeleted != b.isDeleted { return a.isDeleted ? a : b }
        return a.displayName >= b.displayName ? a : b
    }

    private static func pickGroup(_ a: FriendGroup, _ b: FriendGroup) -> FriendGroup {
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt ? a : b }
        if a.isDeleted != b.isDeleted { return a.isDeleted ? a : b }
        return a.name >= b.name ? a : b
    }
}
