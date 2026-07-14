import Foundation

/// A receiver-defined circle of friends. Local only — the share payload knows nothing
/// of groups. Stable `id` (referenced by `Friend.groups`) so a group can be renamed
/// without re-tagging members, and can exist while empty.
public struct FriendGroup: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Last local mutation — sync tiebreaker: newest wins per id.
    public var updatedAt: Date
    /// Soft-delete tombstone: non-nil = deleted then, kept only to propagate the delete.
    public var deletedAt: Date?

    public var isDeleted: Bool { deletedAt != nil }

    /// Keeps the id + deletion time, blanks the name — enough to propagate the delete.
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
