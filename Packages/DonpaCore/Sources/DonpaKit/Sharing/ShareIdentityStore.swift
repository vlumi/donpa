import DonpaCore
import Foundation

/// Keychain storage for the share identity, minted lazily on first use. The item
/// is synchronizable so a second device adopts the existing identity via iCloud
/// Keychain instead of minting a rival one.
public final class ShareIdentityStore {
    private let account = "fi.misaki.donpa.share-identity"
    private let nameAccount = "fi.misaki.donpa.share-name"
    private let service = "fi.misaki.donpa"

    public init() {}

    /// The device's identity, minting + persisting one on first call. Nil only if
    /// the Keychain write fails.
    public func identity() -> ShareIdentity? {
        if let data = load(account: account),
            let id = try? ShareIdentity(privateKeyRepresentation: data)
        {
            return id
        }
        let fresh = ShareIdentity()
        guard store(fresh.privateKeyRepresentation, account: account) else { return nil }
        return fresh
    }

    /// The share display name, a SECOND synchronizable item. NEVER fold it into the
    /// key's item: shipped builds parse that item as raw key bytes, and reformatting
    /// would make a mixed-version sibling device mint a fresh identity. Empty string
    /// is a real value ("cleared everywhere"); nil means never set.
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
        // Delete any stale item first so SecItemAdd can't collide.
        SecItemDelete(baseQuery(account: account) as CFDictionary)
        var q = baseQuery(account: account)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
}
