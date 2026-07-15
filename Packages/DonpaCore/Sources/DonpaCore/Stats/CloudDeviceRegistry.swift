import Foundation

/// The cloud side of the registry, mockable in tests. Entries live under
/// their own key namespace beside the stats blobs and follow the same
/// lifecycle: published only while sync participates, removed with the blob.
@MainActor
public protocol CloudDeviceRegistry: AnyObject {
    var isAvailable: Bool { get }
    func writeOwnEntry(_ data: Data, deviceID: String)
    func deleteOwnEntry(deviceID: String)
    /// Every device's entry, keyed by device id (including this device's own).
    func readAllEntries() -> [String: Data]
}

/// `NSUbiquitousKeyValueStore`-backed registry, entries under
/// `donpa.device.<id>` beside the stats blobs.
@MainActor
public final class UbiquitousDeviceRegistry: CloudDeviceRegistry {
    private static let entryPrefix = "donpa.device."

    private let kvs = NSUbiquitousKeyValueStore.default

    public init() {}

    public var isAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }

    public func writeOwnEntry(_ data: Data, deviceID: String) {
        kvs.set(data, forKey: Self.entryPrefix + deviceID)
        kvs.synchronize()
    }

    public func deleteOwnEntry(deviceID: String) {
        kvs.removeObject(forKey: Self.entryPrefix + deviceID)
        kvs.synchronize()
    }

    public func readAllEntries() -> [String: Data] {
        var out: [String: Data] = [:]
        for (key, value) in kvs.dictionaryRepresentation
        where key.hasPrefix(Self.entryPrefix) {
            if let data = value as? Data {
                out[String(key.dropFirst(Self.entryPrefix.count))] = data
            }
        }
        return out
    }
}
