import CryptoKit
import Foundation

/// The device's share identity — a Curve25519 signing keypair. The PUBLIC key is
/// the share ID (knowing it doesn't let anyone sign as you); every share is signed
/// so a receiver can pin the key (TOFU) and trust later shares from the same ID.
///
/// Minted LAZILY at first share (not first launch), so a player who never shares
/// never generates one and one-device sharers never collide. The private key lives
/// in the Keychain as a **synchronizable** item (iCloud Keychain propagates it, so a
/// second device adopts the existing identity instead of minting a rival one).
///
/// This type is the pure crypto core — sign/verify/encode. Keychain persistence and
/// lazy-mint policy live in `ShareIdentityStore` (DonpaKit), so `DonpaCore` stays
/// headless and this stays unit-testable with in-memory keys.
public struct ShareIdentity: Sendable {
    private let privateKey: Curve25519.Signing.PrivateKey

    /// The share ID: the raw 32-byte public key.
    public var publicKey: Data { privateKey.publicKey.rawRepresentation }

    /// Wrap an existing private key (loaded from the Keychain).
    public init(privateKeyRepresentation: Data) throws {
        self.privateKey = try Curve25519.Signing.PrivateKey(
            rawRepresentation: privateKeyRepresentation)
    }

    /// Mint a fresh identity.
    public init() {
        self.privateKey = Curve25519.Signing.PrivateKey()
    }

    /// The private key's raw bytes, for Keychain storage. Handle as a secret.
    public var privateKeyRepresentation: Data { privateKey.rawRepresentation }

    /// Sign an assembled body + assemble the full signed payload. `career`/`rotation`
    /// are already decided by the caller. Signs the CANONICAL body encoding so the
    /// same bytes are verified on the other side (see `ShareCodec.canonicalBody`).
    public func makePayload(
        name: String, scores: [SharedConfigScore], career: SharedCareer?,
        issuedAt: Date, rotation: RotationEndorsement? = nil
    ) throws -> SharePayload {
        let body = ShareBody(
            name: name, scores: scores, career: career, issuedAt: issuedAt, rotation: rotation)
        let signed = try ShareCodec.canonicalBody(body)
        let sig = try privateKey.signature(for: signed)
        return SharePayload(publicKey: publicKey, signature: sig, body: body)
    }

    /// Endorse a NEW public key with THIS (old) key — the rotation signature that
    /// lets friends pinned to this identity migrate to `newPublicKey` silently.
    public func endorse(newPublicKey: Data) throws -> RotationEndorsement {
        let sig = try privateKey.signature(for: newPublicKey)
        return RotationEndorsement(oldPublicKey: publicKey, signature: sig)
    }

    // MARK: Verification (static — no private key needed)

    /// Whether `payload`'s signature is a valid signature by its own `publicKey` over
    /// its body. The FIRST gate on any received share — a bad signature means the
    /// payload was tampered with or forged; reject loudly.
    public static func verify(_ payload: SharePayload) -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: payload.publicKey),
            let signed = try? ShareCodec.canonicalBody(payload.body)
        else { return false }
        return key.isValidSignature(payload.signature, for: signed)
    }

    /// Whether a rotation endorsement genuinely vouches for `newPublicKey`: the
    /// endorsement's signature must be a valid signature BY `oldPublicKey` OVER
    /// `newPublicKey`. Lets a receiver migrate a friend pinned to `oldPublicKey`.
    public static func verifyRotation(_ r: RotationEndorsement, newPublicKey: Data) -> Bool {
        guard let old = try? Curve25519.Signing.PublicKey(rawRepresentation: r.oldPublicKey)
        else { return false }
        return old.isValidSignature(r.signature, for: newPublicKey)
    }
}
