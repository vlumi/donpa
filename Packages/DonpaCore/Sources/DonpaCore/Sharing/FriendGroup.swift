import Foundation

/// A receiver-defined circle of friends (e.g. "work", "family"). Local only — the
/// share payload knows nothing of groups. A real object with a stable `id` so a group
/// can be renamed (members reference the id, not the name) and can exist while empty.
/// `Friend.groups` holds these ids.
public struct FriendGroup: Codable, Equatable, Sendable, Identifiable {
    /// Stable identity, independent of the name — lets a group be renamed without
    /// re-tagging its members. A short opaque string (UUID by default).
    public var id: String
    /// The display name. Not unique-enforced at the type level; the store trims and
    /// rejects blank/duplicate names when creating or renaming.
    public var name: String
    /// Last local mutation (create / rename). Sync tiebreaker: newest wins per id.
    public var updatedAt: Date
    /// Soft-delete tombstone; non-nil = deleted then, kept only to propagate the
    /// delete across devices. nil = live.
    public var deletedAt: Date?

    /// A tombstoned group — deleted, retained only to propagate the delete.
    public var isDeleted: Bool { deletedAt != nil }

    /// A minimal tombstone: keep the id + deletion time, blank the name. Enough for
    /// the merge to propagate the delete without the name lingering.
    public func tombstone(now: Date = Date()) -> FriendGroup {
        FriendGroup(id: id, name: "", updatedAt: now, deletedAt: now)
    }

    public init(
        id: String = UUID().uuidString, name: String,
        updatedAt: Date = Date(), deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        // Pre-sync groups lack these: an old catalog entry is "live, epoch 0".
        updatedAt =
            try c.decodeIfPresent(Date.self, forKey: .updatedAt)
            ?? Date(timeIntervalSince1970: 0)
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, name = "n", updatedAt = "u", deletedAt = "d"
    }
}
