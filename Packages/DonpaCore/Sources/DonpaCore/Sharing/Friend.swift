import Foundation

/// A tracked friend — a share pinned on first scan (TOFU). Lives only in the friends
/// store, never merged into your own stats, so deleting a friend leaves nothing to
/// clean up.
public struct Friend: Codable, Equatable, Sendable, Identifiable {
    /// The pinned share identity (32 B public key) — the stable ID across re-scans.
    public var publicKey: Data
    /// Name from the friend's latest accepted share (sanitized); never edited locally.
    public var sharedName: String
    /// Local-only alias: never touched by an incoming share, wins over `sharedName`
    /// for display.
    public var localAlias: String?
    /// Local-only `FriendGroup` ids (ids, not names, so a rename doesn't re-tag members).
    public var groups: [String]
    /// Latest accepted share's `issuedAt` — replay/downgrade guard: older shares are ignored.
    public var lastIssuedAt: Date
    public var scores: [SharedConfigScore]
    /// Daily results, accumulated PER DATE across shares: each card carries
    /// a window, and the newest share wins the dates it covers while older
    /// dates survive — long rivalries build full histories organically.
    public var dailies: [String: SharedDailyDay]
    public var career: SharedCareer?
    public var addedAt: Date
    /// Last local mutation — the sync tiebreaker: newest wins per friend across devices.
    public var updatedAt: Date
    /// Soft-delete tombstone: non-nil = removed then, kept in the synced blob so the
    /// delete propagates and can't resurrect. nil = live.
    public var deletedAt: Date?

    public var id: Data { publicKey }

    public var displayName: String { localAlias ?? sharedName }

    public var isDeleted: Bool { deletedAt != nil }

    /// Keeps only the public key + deletion time — enough to propagate the delete
    /// without the friend's data lingering in the synced blob.
    public func tombstone(now: Date = Date()) -> Friend {
        Friend(
            publicKey: publicKey, sharedName: "", localAlias: nil, groups: [],
            lastIssuedAt: lastIssuedAt, scores: [], career: nil, addedAt: addedAt,
            updatedAt: now, deletedAt: now)
    }

    public init(
        publicKey: Data, sharedName: String, localAlias: String? = nil, groups: [String] = [],
        lastIssuedAt: Date, scores: [SharedConfigScore],
        dailies: [String: SharedDailyDay] = [:], career: SharedCareer?, addedAt: Date,
        updatedAt: Date? = nil, deletedAt: Date? = nil
    ) {
        self.publicKey = publicKey
        self.sharedName = sharedName
        self.localAlias = localAlias
        self.groups = groups
        self.lastIssuedAt = lastIssuedAt
        self.scores = scores
        self.dailies = dailies
        self.career = career
        self.addedAt = addedAt
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
        dailies =
            try c.decodeIfPresent([String: SharedDailyDay].self, forKey: .dailies) ?? [:]
        career = try c.decodeIfPresent(SharedCareer.self, forKey: .career)
        addedAt = try c.decode(Date.self, forKey: .addedAt)
        // Pre-sync records lack these: default updatedAt to addedAt, no tombstone.
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? addedAt
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    enum CodingKeys: String, CodingKey {
        case publicKey = "pk", sharedName = "n", localAlias = "la", groups = "g"
        case lastIssuedAt = "t", scores = "s", dailies = "y", career = "c", addedAt = "a"
        case updatedAt = "u", deletedAt = "d"
    }
}
