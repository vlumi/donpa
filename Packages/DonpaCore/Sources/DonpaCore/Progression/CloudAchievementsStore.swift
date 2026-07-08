import Foundation

/// The iCloud transport for the earned-achievement set — same per-device-blob
/// scheme as the scoreboard and friends stacks, own key namespace. Union-only
/// data (achievements never delete), so the merge needs no tombstones and no
/// reset-epoch: feats are PERMANENT by decision (the stats wipe must not touch
/// them — hidden feats can't be re-derived and Game Center can't un-report).
public protocol CloudAchievementsStore: AnyObject {
    /// Whether iCloud is available; when false, reads/writes are no-ops.
    var isAvailable: Bool { get }

    /// Write this device's encoded earned blob to its own slot.
    func writeOwnBlob(_ data: Data, deviceID: String)

    /// Remove this device's own slot (on sync-off) so it stops contributing.
    /// Other slots — and the local store — are untouched.
    func deleteOwnBlob(deviceID: String)

    /// Every device's blob, keyed by device id (including this device's own).
    func readAllBlobs() -> [String: Data]

    /// Hint the store to push/pull now (best-effort).
    func synchronize()

    /// Called on external cloud change, so the host re-merges and refreshes.
    var onExternalChange: (() -> Void)? { get set }
}

/// `NSUbiquitousKeyValueStore`-backed achievements store. Per-device blobs live
/// under keys prefixed `donpa.ach.blob.` — a separate namespace from the
/// scoreboard's and friends' blobs, on the same KVS.
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
