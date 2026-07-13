import Foundation

/// Encodes/decodes a `SharePayload` for transport (Universal Link / QR) and applies
/// every hardening guard on the way IN. The format is compressed JSON in a versioned
/// envelope — JSON because `JSONDecoder` is memory-safe (malformed input throws, no
/// code path), and a hand-rolled binary format would be LESS safe (offset math).
/// Security is the SIGNATURE, not secrecy: the payload is public by design.
public enum ShareCodec {
    /// Reasons a received blob is refused. Distinct cases so the UI can tell a
    /// tampered/forged share (loud reject) from a merely-unsupported newer version.
    public enum DecodeError: Error, Equatable {
        case notDonpaShare  // wrong base64url / not our JSON
        case tooLarge  // decompression-bomb guard tripped
        case unsupportedVersion  // newer envelope than we understand
        case malformed  // JSON shape wrong / values out of range
        case badSignature  // signature doesn't verify against its own key
    }

    /// Hard cap on decompressed bytes — a decompression-bomb guard. A legitimate
    /// share (bests-only, ~all configs) is a few KB; 64 KB is generous headroom.
    static let maxDecompressedBytes = 64 * 1024
    /// Display-name length cap (characters), after sanitization.
    static let maxNameLength = 40

    // MARK: Canonical body encoding (what gets signed)

    /// Deterministic JSON encoding of a `ShareBody` — sorted keys so the signer and
    /// verifier hash the SAME bytes. Never change this without a version bump.
    static func canonicalBody(_ body: ShareBody) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try enc.encode(body)
    }

    // MARK: Encode (outgoing — trusted, our own data)

    /// Compress a payload to the compact bytes that go into the link/QR.
    public static func encode(_ payload: SharePayload) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = try enc.encode(payload)
        return (try? (json as NSData).compressed(using: .zlib) as Data) ?? json
    }

    /// base64url (URL-safe, unpadded) for embedding in the Universal Link path.
    public static func encodeToString(_ payload: SharePayload) throws -> String {
        base64url(try encode(payload))
    }

    // MARK: Decode (incoming — UNTRUSTED; every guard applies here)

    /// Decode + fully validate an incoming blob. Runs in order: decompress (bomb
    /// guard) → version check → JSON shape → signature → semantic sanitization.
    /// Returns a payload whose `body` has been sanitized (name cleaned, values
    /// clamped-or-rejected). A `throw` means DO NOT trust — surface the reason.
    public static func decode(_ data: Data) throws -> SharePayload {
        let json = try decompress(data)
        guard json.count <= maxDecompressedBytes else { throw DecodeError.tooLarge }

        let dec = JSONDecoder()
        guard let payload = try? dec.decode(SharePayload.self, from: json) else {
            throw DecodeError.malformed
        }
        guard payload.version <= SharePayload.currentVersion else {
            throw DecodeError.unsupportedVersion
        }
        guard payload.version >= 1, payload.publicKey.count == 32, payload.signature.count == 64
        else { throw DecodeError.malformed }

        // Signature BEFORE trusting any field — proves the body is authentic to its
        // key. (Sanitization below doesn't affect the signed bytes; we sign/verify
        // the raw body, then present a cleaned copy.)
        guard ShareIdentity.verify(payload) else { throw DecodeError.badSignature }

        let clean = try sanitize(payload.body)
        return SharePayload(
            version: payload.version, publicKey: payload.publicKey,
            signature: payload.signature, body: clean)
    }

    /// Decode from the link's base64url string.
    public static func decode(fromString s: String) throws -> SharePayload {
        guard let data = dataFromBase64url(s) else { throw DecodeError.notDonpaShare }
        return try decode(data)
    }

    // MARK: Sanitization (semantic guards on the decoded body)

    /// Reject or clean out-of-range / hostile fields. Rejects (throws `.malformed`)
    /// on structurally-impossible values; cleans cosmetic ones (name).
    static func sanitize(_ body: ShareBody) throws -> ShareBody {
        let name = sanitizeName(body.name)
        var scores: [SharedConfigScore] = []
        var seenKeys = Set<String>()
        for s in body.scores {
            guard isValidStorageKey(s.key), seenKeys.insert(s.key).inserted else {
                throw DecodeError.malformed  // bad grammar or duplicate key
            }
            guard s.wins >= 0, (s.best ?? 0) >= 0 else { throw DecodeError.malformed }
            if let p = s.bestProgress, !(0...1).contains(p) { throw DecodeError.malformed }
            for pace in [s.recentPace, s.bestPace] {
                if let pace, !(pace.isFinite && pace >= 0) { throw DecodeError.malformed }
            }
            scores.append(s)
        }
        if let c = body.career, !careerNonNegative(c) { throw DecodeError.malformed }
        return ShareBody(
            name: name, scores: scores, career: body.career,
            issuedAt: body.issuedAt, rotation: body.rotation)
    }

    /// Length-cap + strip control and bidi-override characters (U+202E etc. spoofing).
    /// Falls back to a placeholder if nothing printable survives.
    static func sanitizeName(_ raw: String) -> String {
        let stripped = raw.unicodeScalars.filter { s in
            // Drop C0/C1 controls and the bidi-override / isolate range that can
            // visually reorder text to spoof a name.
            if s.properties.generalCategory == .control { return false }
            if (0x202A...0x202E).contains(s.value) || (0x2066...0x2069).contains(s.value) {
                return false
            }
            return true
        }
        let cleaned = String(String.UnicodeScalarView(stripped))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let capped = String(cleaned.prefix(maxNameLength))
        return capped.isEmpty ? "?" : capped
    }

    /// The `GameConfig.storageKey` grammar we accept — conservative allowlist so a
    /// hostile key can't inject anything odd into the friends store or comparison UI.
    /// Matches `v<N>|family|edges|WxH|mNN` and the basic form `v<N>|basic|<preset>`.
    static func isValidStorageKey(_ key: String) -> Bool {
        guard key.count <= 40 else { return false }
        // Allowlist chars: lowercase, digits, the field separator, x, the version 'v'.
        let allowed = CharacterSet(
            charactersIn:
                "abcdefghijklmnopqrstuvwxyz0123456789|x")
        guard key.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        let parts = key.split(separator: "|")
        guard parts.count >= 2, parts[0].hasPrefix("v") else { return false }
        return true
    }

    private static func careerNonNegative(_ c: SharedCareer) -> Bool {
        [
            c.gamesPlayed, c.wins, c.tilesOpened, c.flagsPlaced, c.minesDisarmed,
            c.minesHit, c.chordsUsed, c.noFlagWins, c.noChordWins, c.playtimeCentiseconds,
        ].allSatisfy { $0 >= 0 }
    }

    // MARK: Transport helpers

    private static func decompress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { throw DecodeError.notDonpaShare }
        // Uncompressed JSON (starts with '{') is accepted directly; else zlib.
        if data.first == UInt8(ascii: "{") { return data }
        guard let out = try? (data as NSData).decompressed(using: .zlib) as Data, !out.isEmpty
        else { throw DecodeError.notDonpaShare }
        return out
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func dataFromBase64url(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b.append("=") }
        return Data(base64Encoded: b)
    }
}
