import Foundation

/// A tracked friend — a share pinned on first scan (TOFU). Lives ONLY in the
/// friends store, never merged into your own stats (the display-merge invariant):
/// deleting a friend makes their rows vanish with nothing to clean up.
public struct Friend: Codable, Equatable, Sendable, Identifiable {
    /// The pinned share identity (public key, 32 B) — the stable ID across re-scans.
    public var publicKey: Data
    /// Display name from the most recent accepted share (sanitized).
    public var name: String
    /// Receiver-assigned group tags (local only — the payload knows nothing of
    /// groups). Empty = ungrouped. Tag-style: a friend can be in several.
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

    public init(
        publicKey: Data, name: String, groups: [String] = [], lastIssuedAt: Date,
        scores: [SharedConfigScore], career: SharedCareer?, addedAt: Date
    ) {
        self.publicKey = publicKey
        self.name = name
        self.groups = groups
        self.lastIssuedAt = lastIssuedAt
        self.scores = scores
        self.career = career
        self.addedAt = addedAt
    }

    enum CodingKeys: String, CodingKey {
        case publicKey = "pk", name = "n", groups = "g", lastIssuedAt = "t"
        case scores = "s", career = "c", addedAt = "a"
    }
}
