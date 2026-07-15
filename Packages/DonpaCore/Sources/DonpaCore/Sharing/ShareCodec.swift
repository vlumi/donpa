import Foundation

/// Encodes/decodes a `SharePayload` for transport (Universal Link / QR) and applies
/// every hardening guard on the way in. Format: compressed JSON in a versioned
/// envelope — JSON deliberately, for memory-safe decoding over hand-rolled binary.
/// Security is the SIGNATURE, not secrecy: the payload is public by design.
public enum ShareCodec {
    /// Distinct cases so the UI can tell a tampered/forged share (loud reject) from
    /// a merely-unsupported newer version.
    public enum DecodeError: Error, Equatable {
        case notDonpaShare  // wrong base64url / not our JSON
        case tooLarge  // decompression-bomb guard tripped
        case unsupportedVersion  // newer envelope than we understand
        case malformed  // JSON shape wrong / values out of range
        case badSignature  // signature doesn't verify against its own key
    }

    /// Decompression-bomb cap; a legitimate share is a few KB.
    static let maxDecompressedBytes = 64 * 1024
    static let maxNameLength = 40

    /// Deterministic encoding of the signed body — sorted keys so signer and
    /// verifier hash the SAME bytes. Never change this without a version bump.
    static func canonicalBody(_ body: ShareBody) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try enc.encode(body)
    }

    // MARK: Encode (outgoing — trusted, our own data)

    public static func encode(_ payload: SharePayload) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = try enc.encode(payload)
        return (try? (json as NSData).compressed(using: .zlib) as Data) ?? json
    }

    public static func encodeToString(_ payload: SharePayload) throws -> String {
        base64url(try encode(payload))
    }

    // MARK: Decode (incoming — UNTRUSTED; every guard applies here)

    /// Guards run in order: decompress (bomb guard) → version → JSON shape →
    /// signature → semantic sanitization. A throw means DO NOT trust.
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

        // Signature BEFORE trusting any field. Sanitization doesn't affect the
        // signed bytes: verify the raw body, then present a cleaned copy.
        guard ShareIdentity.verify(payload) else { throw DecodeError.badSignature }

        let clean = try sanitize(payload.body)
        return SharePayload(
            version: payload.version, publicKey: payload.publicKey,
            signature: payload.signature, body: clean)
    }

    public static func decode(fromString s: String) throws -> SharePayload {
        guard let data = dataFromBase64url(s) else { throw DecodeError.notDonpaShare }
        return try decode(data)
    }

    // MARK: Sanitization

    /// Throws `.malformed` on structurally-impossible values; cleans cosmetic ones
    /// (name).
    static func sanitize(_ body: ShareBody) throws -> ShareBody {
        let name = sanitizeName(body.name)
        var scores: [SharedConfigScore] = []
        var seenKeys = Set<String>()
        for s in body.scores {
            guard isValidStorageKey(s.key), seenKeys.insert(s.key).inserted else {
                throw DecodeError.malformed
            }
            guard s.wins >= 0, (s.best ?? 0) >= 0 else { throw DecodeError.malformed }
            if let p = s.bestProgress, !(0...1).contains(p) { throw DecodeError.malformed }
            for pace in [s.recentPace, s.bestPace] {
                if let pace, !(pace.isFinite && pace >= 0) { throw DecodeError.malformed }
            }
            scores.append(s)
        }
        if let c = body.career, !careerNonNegative(c) { throw DecodeError.malformed }
        try validateDaily(body.daily)
        return ShareBody(
            name: name, scores: scores, career: body.career, daily: body.daily,
            issuedAt: body.issuedAt, rotation: body.rotation)
    }

    /// Caps length and strips control + bidi-override/isolate characters (U+202E-style
    /// name spoofing); falls back to a placeholder if nothing printable survives.
    /// Day keys are strict "yyyy-MM-dd", unique; values non-negative and
    /// finite; the window is capped (the byte bomb-guard is upstream, this
    /// keeps a hostile share from flooding the friend store with rows).
    static func validateDaily(_ daily: [SharedDailyDay]?) throws {
        guard let daily else { return }
        guard daily.count <= 400 else { throw DecodeError.malformed }
        var seen = Set<String>()
        for day in daily {
            guard let ordinal = DailyChallenge.dayOrdinal(of: day.key),
                DailyMerge.dateKey(ordinal: ordinal) == day.key,
                seen.insert(day.key).inserted
            else { throw DecodeError.malformed }
            guard (day.best ?? 0) >= 0, (day.threeBV ?? 0) >= 0, day.attempts >= 0
            else { throw DecodeError.malformed }
            if let p = day.progress, !(p.isFinite && (0...1).contains(p)) {
                throw DecodeError.malformed
            }
        }
    }

    static func sanitizeName(_ raw: String) -> String {
        let stripped = raw.unicodeScalars.filter { s in
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

    /// Conservative allowlist for the `GameConfig.storageKey` grammar, so a hostile
    /// key can't inject anything odd into the friends store or comparison UI.
    static func isValidStorageKey(_ key: String) -> Bool {
        guard key.count <= 40 else { return false }
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
        // Plain JSON (encode's fallback when compression fails) passes through.
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
