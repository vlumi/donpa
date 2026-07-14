import Foundation

/// One config's shared figures, keyed by `GameConfig.storageKey`. Deliberately a
/// subset of `ScoreRecord`: bests + wins are all a head-to-head needs, and staying
/// small keeps the QR/URL within capacity (top-time lists stay private).
public struct SharedConfigScore: Codable, Equatable, Sendable {
    /// Matched against the receiver's locally-enumerated configs — never parsed back
    /// into a `GameConfig`.
    public var key: String
    /// Best winning time in centiseconds; nil = never won.
    public var best: Int?
    public var wins: Int
    /// Best cleared fraction (0…1) from a loss; a win implies 100%.
    public var bestProgress: Double?
    /// Recent pace (3BV/s). Envelope v2+.
    public var recentPace: Double?
    /// Best pace (3BV/s) ever logged. Envelope v2+.
    public var bestPace: Double?

    public init(
        key: String, best: Int?, wins: Int, bestProgress: Double?,
        recentPace: Double? = nil, bestPace: Double? = nil
    ) {
        self.key = key
        self.best = best
        self.wins = wins
        self.bestProgress = bestProgress
        self.recentPace = recentPace
        self.bestPace = bestPace
    }

    enum CodingKeys: String, CodingKey {
        case key = "k", best = "b", wins = "w", bestProgress = "p"
        case recentPace = "rp", bestPace = "bp"
    }
}

/// Lifetime career totals; shared only when the sharer opts in at share time.
public struct SharedCareer: Codable, Equatable, Sendable {
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

/// The inner, SIGNED body of a share — every field here is covered by the signature,
/// so a tampered field fails verification.
public struct ShareBody: Codable, Equatable, Sendable {
    /// Display name the sharer typed at share time; sanitized on receive.
    public var name: String
    public var scores: [SharedConfigScore]
    public var career: SharedCareer?
    /// The replay/downgrade guard: a receiver keeps only the newest per identity.
    public var issuedAt: Date
    /// The sharer's PREVIOUS identity signing this new public key, letting friends
    /// pinned to the old key migrate silently.
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

/// A previous identity vouching for a new one, so a receiver can migrate a friend
/// pinned to `oldPublicKey` without a prompt.
public struct RotationEndorsement: Codable, Equatable, Sendable {
    /// The retired identity's public key (32 B).
    public var oldPublicKey: Data
    /// Signature by the OLD private key over the NEW public key (64 B).
    public var signature: Data

    public init(oldPublicKey: Data, signature: Data) {
        self.oldPublicKey = oldPublicKey
        self.signature = signature
    }

    enum CodingKeys: String, CodingKey { case oldPublicKey = "ok", signature = "os" }
}

/// The complete share artifact — versioned envelope, signer's public key, signature
/// over the canonical-encoded `ShareBody`, and the body. Compressed → base64url →
/// embedded in the Universal Link / QR.
public struct SharePayload: Codable, Equatable, Sendable {
    /// Envelope format version; a receiver rejects versions it doesn't understand.
    /// ANY new body field needs a bump — verification re-encodes the decoded body,
    /// so an older app would drop the unknown field and read a legitimate share as
    /// tampered instead of merely too new.
    public var version: Int
    /// The sharer's Curve25519 signing public key (32 B) — their share identity.
    public var publicKey: Data
    /// Detached signature over the canonical body (64 B).
    public var signature: Data
    public var body: ShareBody

    public static let currentVersion = 2

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
