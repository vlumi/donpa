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

    public var id: Data { publicKey }

    /// What to show: your local alias if you set one, else the friend's own name.
    public var displayName: String { localAlias ?? sharedName }

    public init(
        publicKey: Data, sharedName: String, localAlias: String? = nil, groups: [String] = [],
        lastIssuedAt: Date, scores: [SharedConfigScore], career: SharedCareer?, addedAt: Date
    ) {
        self.publicKey = publicKey
        self.sharedName = sharedName
        self.localAlias = localAlias
        self.groups = groups
        self.lastIssuedAt = lastIssuedAt
        self.scores = scores
        self.career = career
        self.addedAt = addedAt
    }

    enum CodingKeys: String, CodingKey {
        case publicKey = "pk", sharedName = "n", localAlias = "la", groups = "g"
        case lastIssuedAt = "t", scores = "s", career = "c", addedAt = "a"
    }
}
