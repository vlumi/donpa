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
    private let nameAccount = "fi.misaki.donpa.share-name"
    private let service = "fi.misaki.donpa"

    public init() {}

    /// The device's identity, minting + persisting one on first call. Returns nil
    /// only if the Keychain write genuinely fails (rare; caller can surface "couldn't
    /// prepare sharing" rather than crash).
    public func identity() -> ShareIdentity? {
        if let data = load(account: account),
            let id = try? ShareIdentity(privateKeyRepresentation: data)
        {
            return id
        }
        // Lazy mint: no key yet → create, store, return. (First share only.)
        let fresh = ShareIdentity()
        guard store(fresh.privateKeyRepresentation, account: account) else { return nil }
        return fresh
    }

    /// The share display name — the other half of the identity, kept as a SECOND
    /// synchronizable item so it rides the same iCloud Keychain rail as the key.
    /// Deliberately NOT folded into the key's item: released builds parse that item
    /// as raw key bytes, and reformatting it would make a mixed-version sibling
    /// device fail the parse and mint a fresh identity. An empty string is a real
    /// value ("cleared everywhere"); nil means never set (or Keychain unavailable).
    public var sharedName: String? {
        get {
            guard let data = load(account: nameAccount) else { return nil }
            return String(bytes: data, encoding: .utf8)
        }
        set {
            guard let newValue else {
                SecItemDelete(baseQuery(account: nameAccount) as CFDictionary)
                return
            }
            _ = store(Data(newValue.utf8), account: nameAccount)
        }
    }

    // MARK: Keychain

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // Propagate via iCloud Keychain so sibling devices share one identity.
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
        ]
    }

    private func load(account: String) -> Data? {
        var q = baseQuery(account: account)
        q[kSecReturnData as String] = kCFBooleanTrue
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    private func store(_ data: Data, account: String) -> Bool {
        // Delete any stale item first so add can't collide.
        SecItemDelete(baseQuery(account: account) as CFDictionary)
        var q = baseQuery(account: account)
        q[kSecValueData as String] = data
        // Available after first unlock, including in the background; the key is not
        // needed pre-unlock and this class is the most permissive that still
        // requires the device to have been unlocked once.
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
}
