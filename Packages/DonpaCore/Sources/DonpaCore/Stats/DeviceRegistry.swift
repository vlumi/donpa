import Foundation

/// One device's self-description, published beside its stats blob so future
/// readers (record attribution, playtime by device class, a "Your devices"
/// list) can name the blob's `DeviceID`. Collection ships ahead of every
/// reader — attribution can't be backfilled. Never enters the share payload.
public struct DeviceInfo: Codable, Equatable, Sendable {
    public enum DeviceClass: String, Codable, Sendable {
        case phone, pad, mac
    }

    /// The live platform facts a device publishes about itself.
    public struct Facts: Equatable, Sendable {
        public let name: String
        public let model: String
        public let deviceClass: DeviceClass

        public init(name: String, model: String, deviceClass: DeviceClass) {
            self.name = name
            self.model = model
            self.deviceClass = deviceClass
        }
    }

    public var id: String
    /// User-visible name where the platform gives it honestly (macOS); the
    /// humanized model elsewhere (iOS 16 returns a generic name without the
    /// user-assigned-device-name entitlement — revisit with the devices UI).
    public var name: String
    /// The hardware identifier, e.g. "iPhone17,3" / "Mac16,10".
    public var model: String
    public var deviceClass: DeviceClass
    public var firstSeen: Date
    public var lastActive: Date

    public init(
        id: String, name: String, model: String, deviceClass: DeviceClass,
        firstSeen: Date, lastActive: Date
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.deviceClass = deviceClass
        self.firstSeen = firstSeen
        self.lastActive = lastActive
    }

    enum CodingKeys: String, CodingKey {
        case id, name, model
        case deviceClass = "class"
        case firstSeen = "first"
        case lastActive = "active"
    }
}

/// Publishes this device's `DeviceInfo` and reads the household's. Registry
/// data is infrastructure, not stats: the wipe never touches it (a reset
/// epoch has nothing to tombstone here); toggling sync off removes the own
/// entry, mirroring the stats blob.
@MainActor
public final class DeviceRegistry {
    /// Skip the refresh write while the published entry is this fresh.
    static let refreshInterval: TimeInterval = 24 * 60 * 60

    private let cloud: CloudDeviceRegistry?
    private let deviceID: String

    public init(cloud: CloudDeviceRegistry?, deviceID: String) {
        self.cloud = cloud
        self.deviceID = deviceID
    }

    /// Publish or freshen this device's entry. `describe` supplies the live
    /// platform facts; `now` is injected for the staleness tests.
    public func refreshOwnEntry(
        syncEnabled: Bool, describe: () -> DeviceInfo.Facts, now: Date = Date()
    ) {
        guard let cloud, cloud.isAvailable else { return }
        guard syncEnabled else {
            cloud.deleteOwnEntry(deviceID: deviceID)
            return
        }
        let existing = Self.decode(cloud.readAllEntries()[deviceID])
        let facts = describe()
        if let existing, existing.name == facts.name, existing.model == facts.model,
            existing.deviceClass == facts.deviceClass,
            now.timeIntervalSince(existing.lastActive) < Self.refreshInterval
        {
            return
        }
        let entry = DeviceInfo(
            id: deviceID, name: facts.name, model: facts.model,
            deviceClass: facts.deviceClass,
            firstSeen: existing?.firstSeen ?? now, lastActive: now)
        if let data = try? JSONEncoder().encode(entry) {
            cloud.writeOwnEntry(data, deviceID: deviceID)
        }
    }

    /// Every known device, own included, newest-active first.
    public func knownDevices() -> [DeviceInfo] {
        guard let cloud, cloud.isAvailable else { return [] }
        return cloud.readAllEntries().values
            .compactMap(Self.decode)
            .sorted { $0.lastActive > $1.lastActive }
    }

    private static func decode(_ data: Data?) -> DeviceInfo? {
        data.flatMap { try? JSONDecoder().decode(DeviceInfo.self, from: $0) }
    }
}
