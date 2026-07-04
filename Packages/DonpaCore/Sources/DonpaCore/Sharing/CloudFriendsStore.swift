import Foundation

/// The cloud side of friend-list sync, abstracted off `NSUbiquitousKeyValueStore`
/// so it's mockable in tests. Same **one blob per device** layout as the scoreboard's
/// `CloudStatsStore`: each device writes only its own slot (keyed by `DeviceID`) and
/// reads every slot to merge (`FriendSyncMerge`). Records carry tombstones, so a
/// delete on one device propagates through that device's blob.
@MainActor
public protocol CloudFriendsStore: AnyObject {
    /// Whether iCloud is available; when false, reads/writes are no-ops.
    var isAvailable: Bool { get }

    /// Write this device's encoded friends blob to its own slot.
    func writeOwnBlob(_ data: Data, deviceID: String)

    /// Remove this device's own slot (on sync-off).
    func deleteOwnBlob(deviceID: String)

    /// Every device's blob, keyed by device id (including this device's own).
    func readAllBlobs() -> [String: Data]

    /// Hint the store to push/pull now (best-effort).
    func synchronize()

    /// Called on external cloud change or iCloud account change, so the host
    /// re-merges and refreshes.
    var onExternalChange: (() -> Void)? { get set }
}

#if canImport(Foundation)
/// `NSUbiquitousKeyValueStore`-backed friends store. Per-device blobs live under keys
/// prefixed `donpa.friends.blob.` — a separate namespace from the scoreboard's blobs,
/// on the same KVS.
@MainActor
public final class UbiquitousFriendsStore: CloudFriendsStore {
    private static let blobPrefix = "donpa.friends.blob."

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
#endif
