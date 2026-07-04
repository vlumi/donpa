import Foundation

/// One config's shared figures — the subset of `ScoreRecord` a friend needs to
/// compare, keyed by `GameConfig.storageKey`. Deliberately NOT the whole record:
/// bests + win count are all a head-to-head needs, and keeping it small holds the
/// QR/URL within capacity (top-time lists stay private). Career totals ride
/// separately in `SharePayload.career`, opt-in at share time.
public struct SharedConfigScore: Codable, Equatable, Sendable {
    /// The config's `storageKey` (e.g. `v2|grid|flat|16x16|m31`). Matched against the
    /// receiver's locally-enumerated configs — never parsed back into a `GameConfig`.
    public var key: String
    /// Best winning time in centiseconds, or nil if never won.
    public var best: Int?
    /// Total wins on this config.
    public var wins: Int
    /// Best cleared fraction (0…1) from a loss, or nil. A win implies 100%.
    public var bestProgress: Double?

    public init(key: String, best: Int?, wins: Int, bestProgress: Double?) {
        self.key = key
        self.best = best
        self.wins = wins
        self.bestProgress = bestProgress
    }

    enum CodingKeys: String, CodingKey {
        case key = "k", best = "b", wins = "w", bestProgress = "p"
    }
}

/// Lifetime career totals — shared only when the sharer opts in at share time.
/// Mirrors the `StatFigures` career scope (see the scoreboard's `StatBlock`).
public struct SharedCareer: Codable, Equatable, Sendable {
    // Win cluster first (games, wins, and the win-feats beside their parent), then
    // activity counts, then time — matching the scoreboard `StatBlock` display order.
    public var gamesPlayed: Int
    public var wins: Int
    public var noFlagWins: Int
    public var noChordWins: Int
    public var tilesOpened: Int
    public var flagsPlaced: Int
    public var minesDisarmed: Int
    public var minesHit: Int
    public var chordsUsed: Int
    public var playtimeCentiseconds: Int

    public init(
        gamesPlayed: Int, wins: Int, noFlagWins: Int, noChordWins: Int,
        tilesOpened: Int, flagsPlaced: Int, minesDisarmed: Int, minesHit: Int,
        chordsUsed: Int, playtimeCentiseconds: Int
    ) {
        self.gamesPlayed = gamesPlayed
        self.wins = wins
        self.noFlagWins = noFlagWins
        self.noChordWins = noChordWins
        self.tilesOpened = tilesOpened
        self.flagsPlaced = flagsPlaced
        self.minesDisarmed = minesDisarmed
        self.minesHit = minesHit
        self.chordsUsed = chordsUsed
        self.playtimeCentiseconds = playtimeCentiseconds
    }

    enum CodingKeys: String, CodingKey {
        case gamesPlayed = "g", wins = "w", noFlagWins = "nf", noChordWins = "nc"
        case tilesOpened = "t", flagsPlaced = "f", minesDisarmed = "d", minesHit = "h"
        case chordsUsed = "c", playtimeCentiseconds = "pt"
    }
}

/// The inner, SIGNED body of a share. Everything here is covered by the signature,
/// so a tampered field fails verification. The signer's public key IS their share
/// identity; `issuedAt` is the replay/downgrade guard (receiver keeps newest per ID).
public struct ShareBody: Codable, Equatable, Sendable {
    /// Display name the sharer typed AT SHARE TIME (sanitized on receive). Not an
    /// inherent property of the scores — a label the sharer chose for this share.
    public var name: String
    /// Per-config bests + wins.
    public var scores: [SharedConfigScore]
    /// Career totals, present only if the sharer opted in.
    public var career: SharedCareer?
    /// When this share was minted (UTC). Newer supersedes older for the same ID.
    public var issuedAt: Date
    /// Optional rotation endorsement: the sharer's PREVIOUS identity signing THIS
    /// (new) public key, letting friends pinned to the old key migrate silently.
    /// See `ShareIdentity` / the double-mint healing plan.
    public var rotation: RotationEndorsement?

    public init(
        name: String, scores: [SharedConfigScore], career: SharedCareer?,
        issuedAt: Date, rotation: RotationEndorsement? = nil
    ) {
        self.name = name
        self.scores = scores
        self.career = career
        self.issuedAt = issuedAt
        self.rotation = rotation
    }

    enum CodingKeys: String, CodingKey {
        case name = "n", scores = "s", career = "c", issuedAt = "t", rotation = "r"
    }
}

/// A previous identity vouching for a new one: `oldPublicKey` + a signature (by the
/// OLD private key) over the new public key. A receiver holding a friend pinned to
/// `oldPublicKey` can verify this and migrate the pin to the new key with no prompt.
public struct RotationEndorsement: Codable, Equatable, Sendable {
    /// The retired identity's public key (32 B, base64url in JSON).
    public var oldPublicKey: Data
    /// Signature by the OLD private key over the NEW public key (64 B).
    public var signature: Data

    public init(oldPublicKey: Data, signature: Data) {
        self.oldPublicKey = oldPublicKey
        self.signature = signature
    }

    enum CodingKeys: String, CodingKey { case oldPublicKey = "ok", signature = "os" }
}

/// The complete share artifact: a versioned envelope carrying the signer's public
/// key, the signature over the encoded `ShareBody`, and the body itself. This is
/// what gets compressed → base64url → embedded in the Universal Link / QR.
public struct SharePayload: Codable, Equatable, Sendable {
    /// Envelope format version. A receiver rejects a version it doesn't understand
    /// (graceful, not a crash). Bump only on a breaking shape change.
    public var version: Int
    /// The sharer's Curve25519 signing public key (32 B) — their share identity.
    public var publicKey: Data
    /// Detached signature over the canonical-encoded `ShareBody` (64 B).
    public var signature: Data
    /// The signed body.
    public var body: ShareBody

    public static let currentVersion = 1

    public init(version: Int = currentVersion, publicKey: Data, signature: Data, body: ShareBody) {
        self.version = version
        self.publicKey = publicKey
        self.signature = signature
        self.body = body
    }

    enum CodingKeys: String, CodingKey {
        case version = "v", publicKey = "pk", signature = "sig", body = "b"
    }
}
