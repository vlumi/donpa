import Foundation

/// The cloud side of device nicknames, mockable in tests. One KVS key per
/// device, so iCloud's own last-writer-wins IS the per-entry LWW — no merge.
@MainActor
public protocol CloudDeviceNicknames: AnyObject {
    var isAvailable: Bool { get }
    /// Every nickname, keyed by device id.
    func readAll() -> [String: String]
    /// nil clears the entry.
    func write(_ nickname: String?, for deviceID: String)
}

/// `NSUbiquitousKeyValueStore`-backed nicknames under `donpa.deviceNick.<id>`
/// — a namespace of its own, NOT under the registry's `donpa.device.` prefix,
/// so the registry's entry scan never sees them.
@MainActor
public final class UbiquitousDeviceNicknames: CloudDeviceNicknames {
    private static let prefix = "donpa.deviceNick."

    private let kvs = NSUbiquitousKeyValueStore.default

    public init() {}

    public var isAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }

    public func readAll() -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in kvs.dictionaryRepresentation where key.hasPrefix(Self.prefix) {
            if let name = value as? String {
                out[String(key.dropFirst(Self.prefix.count))] = name
            }
        }
        return out
    }

    public func write(_ nickname: String?, for deviceID: String) {
        let key = Self.prefix + deviceID
        if let nickname {
            kvs.set(nickname, forKey: key)
        } else {
            kvs.removeObject(forKey: key)
        }
        kvs.synchronize()
    }
}
