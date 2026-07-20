import Foundation
import Security

/// The real install marker: a generic-password Keychain item marked
/// **ThisDeviceOnly**, so it survives reinstalls and same-device restores but
/// never a transfer onto different hardware — exactly the asymmetry
/// CloneDetection reads. Device-only by nature (tests use a fake).
public final class InstallMarkerKeychain: InstallMarkerStore {
    private let service = "fi.misaki.donpa.install"
    private let account = "marker"

    public init() {}

    public func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return String(bytes: data, encoding: .utf8)
    }

    @discardableResult
    public func mint() -> String {
        let token = UUID().uuidString
        SecItemDelete(baseQuery as CFDictionary)
        var add = baseQuery
        add[kSecValueData as String] = Data(token.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
        return token
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
