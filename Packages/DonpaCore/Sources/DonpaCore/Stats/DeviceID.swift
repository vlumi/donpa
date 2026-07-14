import Foundation

/// Stable per-install id — this device's slot key in iCloud sync. A UserDefaults
/// UUID, not `identifierForVendor` (iOS-only; one scheme is needed across iOS +
/// macOS). Reinstalling mints a new id and abandons the old cloud slot —
/// accepted churn, since a reinstall can't be told from an offline device.
public enum DeviceID {
    static let defaultsKey = "donpa.deviceID"

    public static func current(in defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: defaultsKey) { return existing }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: defaultsKey)
        return fresh
    }
}
