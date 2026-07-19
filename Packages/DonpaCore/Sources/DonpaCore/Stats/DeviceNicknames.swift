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

/// User-assigned device nicknames — the alias layer over the registry's
/// self-published names (those are never overwritten; display shows
/// `nickname ?? name`, the rival-alias pattern). Keyed by DeviceID, so a
/// nickname follows a migrated device and can name a ghost whose registry
/// entry is gone. Sync infrastructure like the registry: wipe-immune,
/// meaningful only while sync is on.
@MainActor
public struct DeviceNicknames {
    /// Matches the share-name cap — a nickname is the same kind of label.
    public static let maxLength = 40

    private let cloud: (any CloudDeviceNicknames)?

    public init(cloud: (any CloudDeviceNicknames)?) {
        self.cloud = cloud
    }

    public func all() -> [String: String] {
        guard let cloud, cloud.isAvailable else { return [:] }
        return cloud.readAll()
    }

    /// Trimmed and capped; whitespace-only clears the entry.
    public func set(_ raw: String, for deviceID: String) {
        guard let cloud, cloud.isAvailable else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        cloud.write(trimmed.isEmpty ? nil : String(trimmed.prefix(Self.maxLength)), for: deviceID)
    }
}
