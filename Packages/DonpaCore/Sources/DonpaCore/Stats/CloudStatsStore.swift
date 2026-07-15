import Foundation

/// The cloud side of scoreboard sync, mockable in tests. One blob per device:
/// each writes only its own slot (keyed by `DeviceID`) and reads all blobs to
/// merge (`StatsMerge`), so there's nothing to conflict-resolve.
@MainActor
public protocol CloudStatsStore: AnyObject {
    /// When false, reads/writes are no-ops.
    var isAvailable: Bool { get }

    func writeOwnBlob(_ data: Data, deviceID: String)

    /// Other slots are untouched.
    func deleteOwnBlob(deviceID: String)

    /// Every device's blob, keyed by device id (including this device's own).
    func readAllBlobs() -> [String: Data]

    /// The global-wipe hammer. Only removes blobs currently visible — an offline
    /// device's blob is dealt with by the reset epoch.
    func deleteAllBlobs()

    /// The reset generation: data written before it is tombstoned. A device
    /// seeing an epoch greater than the one it last honored wipes its own local
    /// store + blob, so an offline device catches up instead of resurrecting.
    /// 0 when never set.
    func readResetEpoch() -> Int

    /// Monotonic; only ever bumped upward.
    func writeResetEpoch(_ epoch: Int)

    /// Hint the store to push/pull now (best-effort).
    func synchronize()

    /// Fires on external cloud change or iCloud account change.
    var onExternalChange: (() -> Void)? { get set }
}

/// `NSUbiquitousKeyValueStore`-backed store.
@MainActor
public final class UbiquitousStatsStore: CloudStatsStore {
    private static let blobPrefix = "donpa.stats.blob."
    private static let resetEpochKey = "donpa.stats.resetEpoch"

    private let kvs = NSUbiquitousKeyValueStore.default
    public var onExternalChange: (() -> Void)?
    private var observer: NSObjectProtocol?

    public init() {
        // The notification's delivery thread is NOT documented as main and the
        // callback re-enters @MainActor code, so marshal via queue: .main.
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

    public func deleteAllBlobs() {
        guard isAvailable else { return }
        for key in kvs.dictionaryRepresentation.keys where key.hasPrefix(Self.blobPrefix) {
            kvs.removeObject(forKey: key)
        }
        kvs.synchronize()
    }

    public func readResetEpoch() -> Int {
        guard isAvailable else { return 0 }
        // longLong is 0 when the key is absent — the pre-wipe baseline.
        return Int(kvs.longLong(forKey: Self.resetEpochKey))
    }

    public func writeResetEpoch(_ epoch: Int) {
        guard isAvailable else { return }
        // Monotonic guard: KVS is eventually consistent, so a wiper working from
        // a stale read could otherwise LOWER the published epoch and split
        // devices into diverging generations.
        let current = Int(kvs.longLong(forKey: Self.resetEpochKey))
        kvs.set(Int64(max(current, epoch)), forKey: Self.resetEpochKey)
        kvs.synchronize()
    }

    public func synchronize() { kvs.synchronize() }
}
