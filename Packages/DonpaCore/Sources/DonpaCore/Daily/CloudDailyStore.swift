import Foundation

/// The cloud side of daily sync, mockable in tests — one blob per device
/// under `donpa.daily.blob.`, beside the scoreboard's.
@MainActor
public protocol CloudDailyStore: AnyObject {
    var isAvailable: Bool { get }
    func writeOwnBlob(_ data: Data, deviceID: String)
    func deleteOwnBlob(deviceID: String)
    func readAllBlobs() -> [String: Data]
    var onExternalChange: (() -> Void)? { get set }
}

/// `NSUbiquitousKeyValueStore`-backed store.
@MainActor
public final class UbiquitousDailyStore: CloudDailyStore {
    private static let blobPrefix = "donpa.daily.blob."

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
        kvs.set(data, forKey: Self.blobPrefix + deviceID)
        kvs.synchronize()
    }

    public func deleteOwnBlob(deviceID: String) {
        kvs.removeObject(forKey: Self.blobPrefix + deviceID)
        kvs.synchronize()
    }

    public func readAllBlobs() -> [String: Data] {
        var out: [String: Data] = [:]
        for (key, value) in kvs.dictionaryRepresentation
        where key.hasPrefix(Self.blobPrefix) {
            if let data = value as? Data {
                out[String(key.dropFirst(Self.blobPrefix.count))] = data
            }
        }
        return out
    }
}
