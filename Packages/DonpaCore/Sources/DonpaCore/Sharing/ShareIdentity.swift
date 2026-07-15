import CryptoKit
import Foundation

/// The device's share identity — a Curve25519 signing keypair. The public key is the
/// share ID; every share is signed so a receiver can pin the key (TOFU) and trust
/// later shares from the same ID. This is the pure crypto core: Keychain persistence
/// and the lazy-mint policy live in `ShareIdentityStore` (DonpaKit), which keeps the
/// private key as a synchronizable Keychain item so a second device adopts the
/// existing identity instead of minting a rival one.
public struct ShareIdentity: Sendable {
    private let privateKey: Curve25519.Signing.PrivateKey

    /// The share ID: the raw 32-byte public key.
    public var publicKey: Data { privateKey.publicKey.rawRepresentation }

    public init(privateKeyRepresentation: Data) throws {
        self.privateKey = try Curve25519.Signing.PrivateKey(
            rawRepresentation: privateKeyRepresentation)
    }

    public init() {
        self.privateKey = Curve25519.Signing.PrivateKey()
    }

    public var privateKeyRepresentation: Data { privateKey.rawRepresentation }

    /// Signs the CANONICAL body encoding so the verifier hashes the same bytes
    /// (see `ShareCodec.canonicalBody`).
    public func makePayload(
        name: String, scores: [SharedConfigScore], career: SharedCareer?,
        daily: [SharedDailyDay]? = nil, issuedAt: Date,
        rotation: RotationEndorsement? = nil
    ) throws -> SharePayload {
        let body = ShareBody(
            name: name, scores: scores, career: career, daily: daily,
            issuedAt: issuedAt, rotation: rotation)
        let signed = try ShareCodec.canonicalBody(body)
        let sig = try privateKey.signature(for: signed)
        return SharePayload(publicKey: publicKey, signature: sig, body: body)
    }

    /// Endorse a NEW public key with THIS (old) key — lets friends pinned to this
    /// identity migrate to `newPublicKey` silently.
    public func endorse(newPublicKey: Data) throws -> RotationEndorsement {
        let sig = try privateKey.signature(for: newPublicKey)
        return RotationEndorsement(oldPublicKey: publicKey, signature: sig)
    }

    // MARK: Verification (static — no private key needed)

    /// The FIRST gate on any received share: is the signature valid by the payload's
    /// own `publicKey` over its body. False = tampered or forged; reject loudly.
    public static func verify(_ payload: SharePayload) -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: payload.publicKey),
            let signed = try? ShareCodec.canonicalBody(payload.body)
        else { return false }
        return key.isValidSignature(payload.signature, for: signed)
    }

    /// Valid iff the endorsement's signature is BY `oldPublicKey` OVER `newPublicKey`.
    public static func verifyRotation(_ r: RotationEndorsement, newPublicKey: Data) -> Bool {
        guard let old = try? Curve25519.Signing.PublicKey(rawRepresentation: r.oldPublicKey)
        else { return false }
        return old.isValidSignature(r.signature, for: newPublicKey)
    }
}
