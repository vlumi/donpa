import Foundation

/// iCloud transport for earned achievements — the same per-device-blob scheme
/// as the stats stack. Union-only data: no tombstones and deliberately no
/// reset-epoch (feats are permanent; the stats wipe must not touch them).
public protocol CloudAchievementsStore: AnyObject {
    /// When false, reads/writes are no-ops.
    var isAvailable: Bool { get }

    func writeOwnBlob(_ data: Data, deviceID: String)

    /// Other slots — and the local store — are untouched.
    func deleteOwnBlob(deviceID: String)

    /// Every device's blob, keyed by device id (including this device's own).
    func readAllBlobs() -> [String: Data]

    /// Hint the store to push/pull now (best-effort).
    func synchronize()

    var onExternalChange: (() -> Void)? { get set }
}

/// `NSUbiquitousKeyValueStore`-backed. `donpa.ach.blob.` is a separate namespace
/// from the scoreboard's and friends' blobs on the same KVS.
@MainActor
public final class UbiquitousAchievementsStore: CloudAchievementsStore {
    private static let blobPrefix = "donpa.ach.blob."

    private let kvs = NSUbiquitousKeyValueStore.default
    public var onExternalChange: (() -> Void)?
    private var observer: NSObjectProtocol?

    public init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: kvs,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onExternalChange?() }
        }
        kvs.synchronize()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    public var isAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }

    public func writeOwnBlob(_ data: Data, deviceID: String) {
        guard isAvailable else { return }
        kvs.set(data, forKey: Self.blobPrefix + deviceID)
        kvs.synchronize()
    }

    public func deleteOwnBlob(deviceID: String) {
        guard isAvailable else { return }
        kvs.removeObject(forKey: Self.blobPrefix + deviceID)
        kvs.synchronize()
    }

    public func readAllBlobs() -> [String: Data] {
        guard isAvailable else { return [:] }
        var out: [String: Data] = [:]
        for (key, value) in kvs.dictionaryRepresentation where key.hasPrefix(Self.blobPrefix) {
            if let data = value as? Data {
                out[String(key.dropFirst(Self.blobPrefix.count))] = data
            }
        }
        return out
    }

    public func synchronize() { kvs.synchronize() }
}
