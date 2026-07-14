import Foundation

/// Cloud side of friend-list sync, abstracted off `NSUbiquitousKeyValueStore` for
/// testability. One blob per device: each device writes only its own slot (keyed by
/// `DeviceID`) and reads every slot to merge; records carry tombstones so a delete
/// propagates through the deleting device's blob.
@MainActor
public protocol CloudFriendsStore: AnyObject {
    /// When false, reads/writes are no-ops.
    var isAvailable: Bool { get }

    func writeOwnBlob(_ data: Data, deviceID: String)

    func deleteOwnBlob(deviceID: String)

    /// Every device's blob, keyed by device id, including this device's own.
    func readAllBlobs() -> [String: Data]

    /// Best-effort hint to push/pull now.
    func synchronize()

    /// Fired on external cloud change or iCloud account change.
    var onExternalChange: (() -> Void)? { get set }
}

#if canImport(Foundation)
/// Blobs live under keys prefixed `donpa.friends.blob.` — a separate namespace from
/// the scoreboard's blobs on the same KVS.
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
