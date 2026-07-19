import Foundation

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
