import Foundation

/// A tracked friend — a share pinned on first scan (TOFU). Lives ONLY in the
/// friends store, never merged into your own stats (the display-merge invariant):
/// deleting a friend makes their rows vanish with nothing to clean up.
public struct Friend: Codable, Equatable, Sendable, Identifiable {
    /// The pinned share identity (public key, 32 B) — the stable ID across re-scans.
    public var publicKey: Data
    /// The name the FRIEND provided, from their most recent accepted share
    /// (sanitized). Refreshed on each accepted share; never edited by the receiver.
    public var sharedName: String
    /// An optional name YOU set for them locally. Never touched by an incoming
    /// share, so it survives their renames. Wins over `sharedName` for display —
    /// lets you disambiguate two same-named friends, or just call them what you like.
    public var localAlias: String?
    /// Receiver-assigned group memberships as `FriendGroup` ids (local only — the
    /// payload knows nothing of groups). Empty = ungrouped. A friend can be in
    /// several. Ids, not names, so a group rename doesn't touch its members.
    public var groups: [String]
    /// The latest accepted share's `issuedAt` — the replay/downgrade guard: a share
    /// older than this is ignored, so re-scanning an old QR can't regress the entry.
    public var lastIssuedAt: Date
    /// The shared scores from the latest accepted share.
    public var scores: [SharedConfigScore]
    /// Shared career totals, if the friend opted in (else nil).
    public var career: SharedCareer?
    /// When first pinned (local wall-clock) — for list ordering / "friends since".
    public var addedAt: Date
    /// Last local mutation (add / alias / groups / refresh). The sync tiebreaker:
    /// across devices the newest `updatedAt` wins per friend (last-writer-wins).
    public var updatedAt: Date
    /// Soft-delete tombstone. Non-nil = removed at that time; excluded from the live
    /// list but kept in the synced blob so the delete propagates and can't resurrect
    /// from a device that still lists the friend. nil = live.
    public var deletedAt: Date?

    public var id: Data { publicKey }

    /// What to show: your local alias if you set one, else the friend's own name.
    public var displayName: String { localAlias ?? sharedName }

    /// A tombstoned friend — removed, retained only to propagate the delete.
    public var isDeleted: Bool { deletedAt != nil }

    /// A minimal tombstone for this friend: keep only the public key + deletion time,
    /// stripping name / scores / career / alias / groups. Enough for the merge to
    /// propagate the delete, without their data lingering in the synced blob.
    public func tombstone(now: Date = Date()) -> Friend {
        Friend(
            publicKey: publicKey, sharedName: "", localAlias: nil, groups: [],
            lastIssuedAt: lastIssuedAt, scores: [], career: nil, addedAt: addedAt,
            updatedAt: now, deletedAt: now)
    }

    public init(
        publicKey: Data, sharedName: String, localAlias: String? = nil, groups: [String] = [],
        lastIssuedAt: Date, scores: [SharedConfigScore], career: SharedCareer?, addedAt: Date,
        updatedAt: Date? = nil, deletedAt: Date? = nil
    ) {
        self.publicKey = publicKey
        self.sharedName = sharedName
        self.localAlias = localAlias
        self.groups = groups
        self.lastIssuedAt = lastIssuedAt
        self.scores = scores
        self.career = career
        self.addedAt = addedAt
        // Default updatedAt to addedAt so records created without one sort sanely.
        self.updatedAt = updatedAt ?? addedAt
        self.deletedAt = deletedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        publicKey = try c.decode(Data.self, forKey: .publicKey)
        sharedName = try c.decode(String.self, forKey: .sharedName)
        localAlias = try c.decodeIfPresent(String.self, forKey: .localAlias)
        groups = try c.decodeIfPresent([String].self, forKey: .groups) ?? []
        lastIssuedAt = try c.decode(Date.self, forKey: .lastIssuedAt)
        scores = try c.decodeIfPresent([SharedConfigScore].self, forKey: .scores) ?? []
        career = try c.decodeIfPresent(SharedCareer.self, forKey: .career)
        addedAt = try c.decode(Date.self, forKey: .addedAt)
        // Pre-sync records lack these: default updatedAt to addedAt, no tombstone.
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? addedAt
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    enum CodingKeys: String, CodingKey {
        case publicKey = "pk", sharedName = "n", localAlias = "la", groups = "g"
        case lastIssuedAt = "t", scores = "s", career = "c", addedAt = "a"
        case updatedAt = "u", deletedAt = "d"
    }
}
