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

    public init(id: String = UUID().uuidString, name: String) {
        self.id = id
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case id, name = "n"
    }
}
