import Foundation

/// Builds and parses the Universal Link that carries a share (the QR encodes this
/// exact URL). Self-contained: the whole signed payload rides in the path
/// (`/s/<base64url-blob>`), so it opens offline with no lookup server.
public enum ShareLink {
    /// Must match the `applinks:` entitlement and the AASA.
    public static let host = "donpa.app"
    /// The AASA `paths` pattern is `/s/*`.
    public static let pathPrefix = "/s/"

    public static func url(for payload: SharePayload) throws -> URL {
        let blob = try ShareCodec.encodeToString(payload)
        var c = URLComponents()
        c.scheme = "https"
        c.host = host
        c.path = pathPrefix + blob
        guard let url = c.url else { throw ShareCodec.DecodeError.malformed }
        return url
    }

    /// Accepts only our host + `/s/` prefix, so an arbitrary opened URL is ignored.
    public static func blob(from url: URL) -> String? {
        guard let host = url.host, host == Self.host || host == "www.\(Self.host)" else {
            return nil
        }
        guard url.path.hasPrefix(pathPrefix) else { return nil }
        let blob = String(url.path.dropFirst(pathPrefix.count))
        return blob.isEmpty ? nil : blob
    }

    /// Same guarantees as `ShareCodec.decode` — a throw means don't trust it.
    public static func payload(from url: URL) throws -> SharePayload {
        guard let blob = blob(from: url) else { throw ShareCodec.DecodeError.notDonpaShare }
        return try ShareCodec.decode(fromString: blob)
    }
}
