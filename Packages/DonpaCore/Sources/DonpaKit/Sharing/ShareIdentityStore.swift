import DonpaCore
import Foundation

/// Persists the device's share identity (the `ShareIdentity` private key) in the
/// Keychain, minting it LAZILY on first use. The item is **synchronizable** so
/// iCloud Keychain propagates it — a second device adopts the existing identity
/// instead of minting a rival one (shrinking the double-mint problem).
///
/// The pure crypto lives in `ShareIdentity` (DonpaCore); this is just storage +
/// the lazy-mint policy, kept in DonpaKit because Keychain access is platform I/O.
public final class ShareIdentityStore {
    private let account = "fi.misaki.donpa.share-identity"
    private let service = "fi.misaki.donpa"

    public init() {}

    /// The device's identity, minting + persisting one on first call. Returns nil
    /// only if the Keychain write genuinely fails (rare; caller can surface "couldn't
    /// prepare sharing" rather than crash).
    public func identity() -> ShareIdentity? {
        if let data = load(), let id = try? ShareIdentity(privateKeyRepresentation: data) {
            return id
        }
        // Lazy mint: no key yet → create, store, return. (First share only.)
        let fresh = ShareIdentity()
        guard store(fresh.privateKeyRepresentation) else { return nil }
        return fresh
    }

    /// Whether an identity has been minted yet (a share has happened). Lets the UI
    /// avoid minting just to check — e.g. "you haven't shared yet" states.
    public var exists: Bool { load() != nil }

    // MARK: Keychain

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // Propagate via iCloud Keychain so sibling devices share one identity.
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
        ]
    }

    private func load() -> Data? {
        var q = baseQuery()
        q[kSecReturnData as String] = kCFBooleanTrue
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    private func store(_ data: Data) -> Bool {
        // Delete any stale item first so add can't collide.
        SecItemDelete(baseQuery() as CFDictionary)
        var q = baseQuery()
        q[kSecValueData as String] = data
        // Available after first unlock, including in the background; the key is not
        // needed pre-unlock and this class is the most permissive that still
        // requires the device to have been unlocked once.
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
}
