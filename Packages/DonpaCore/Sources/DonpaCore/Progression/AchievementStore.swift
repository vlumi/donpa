import Foundation

/// Earned feats: id × tier → date first earned. Local-first (UserDefaults),
/// synced as per-device KVS blobs merged by pure UNION with the EARLIEST date
/// winning. Achievements never delete: no tombstones, no LWW, and deliberately
/// NO reset-epoch — the stats wipe must not touch this store (hidden feats
/// can't be re-derived and Game Center can't un-report).
@MainActor
public final class AchievementStore: ObservableObject {
    /// tier (1-based) → date first earned; one-shot feats live at tier 1.
    @Published public private(set) var earned: [AchievementID: [Int: Date]] = [:]

    private let defaults: UserDefaults
    private let cloud: CloudAchievementsStore?
    private let deviceID: String
    private var syncEnabled: Bool
    private static let defaultsKey = "donpa.achievements.v1"

    public init(
        defaults: UserDefaults = .standard, cloud: CloudAchievementsStore? = nil,
        syncEnabled: Bool = false
    ) {
        self.defaults = defaults
        self.cloud = cloud
        self.deviceID = DeviceID.current(in: defaults)
        self.syncEnabled = syncEnabled
        earned = Self.decode(defaults.data(forKey: Self.defaultsKey)) ?? [:]
        cloud?.onExternalChange = { [weak self] in self?.mergeFromCloud() }
        if syncEnabled {
            publish()
            mergeFromCloud()
        }
    }

    // MARK: Reads

    /// The highest earned tier (0 = nothing yet).
    public func earnedTier(_ id: AchievementID) -> Int {
        earned[id]?.keys.max() ?? 0
    }

    public func firstEarned(_ id: AchievementID, tier: Int = 1) -> Date? {
        earned[id]?[tier]
    }

    // MARK: Writes

    /// False if already earned — the celebration and GC report key off `true`.
    /// An EARLIER date still lowers the stamp: the first earn anywhere wins,
    /// whichever order the devices sync in.
    @discardableResult
    public func record(_ id: AchievementID, tier: Int = 1, at date: Date = Date()) -> Bool {
        if let known = earned[id]?[tier] {
            if date < known {
                earned[id, default: [:]][tier] = date
                persistAndPublish()
            }
            return false
        }
        earned[id, default: [:]][tier] = date
        persistAndPublish()
        return true
    }

    /// The retroactive pass: stamp everything the records prove that isn't held
    /// yet. Returns the fresh stamps for the celebration queue.
    @discardableResult
    public func reconcile(
        derivable: [AchievementID: Int], at date: Date = Date()
    ) -> [(id: AchievementID, tier: Int)] {
        var fresh: [(id: AchievementID, tier: Int)] = []
        for (id, tierCount) in derivable {
            guard tierCount > 0 else { continue }
            for tier in 1...tierCount where earned[id]?[tier] == nil {
                earned[id, default: [:]][tier] = date
                fresh.append((id, tier))
            }
        }
        if !fresh.isEmpty { persistAndPublish() }
        return fresh.sorted { ($0.id.rawValue, $0.tier) < ($1.id.rawValue, $1.tier) }
    }

    /// Off removes this device's slot; local earnings stay (permanence).
    public func setSyncEnabled(_ on: Bool) {
        syncEnabled = on
        if on {
            publish()
            mergeFromCloud()
        } else {
            cloud?.deleteOwnBlob(deviceID: deviceID)
        }
    }

    // MARK: Sync

    private func mergeFromCloud() {
        guard syncEnabled, let cloud, cloud.isAvailable else { return }
        var merged = earned
        for blob in cloud.readAllBlobs().values {
            guard let remote = Self.decode(blob) else { continue }
            for (id, tiers) in remote {
                for (tier, date) in tiers {
                    let known = merged[id]?[tier]
                    if known == nil || date < known! {
                        merged[id, default: [:]][tier] = date
                    }
                }
            }
        }
        guard merged != earned else { return }
        earned = merged
        persistAndPublish()
    }

    /// Publishes the FULL known union, not just own earnings — idempotent under
    /// the union merge, and converges the fleet faster.
    private func publish() {
        guard syncEnabled, let cloud, cloud.isAvailable,
            let data = Self.encode(earned)
        else { return }
        cloud.writeOwnBlob(data, deviceID: deviceID)
    }

    private func persistAndPublish() {
        defaults.set(Self.encode(earned), forKey: Self.defaultsKey)
        publish()
    }

    // MARK: Wire format

    /// {"version":1,"earned":{"win.first":{"1":<date>}}} — string keys
    /// throughout (Int-keyed Codable dictionaries encode as arrays).
    private struct Envelope: Codable {
        var version: Int
        var earned: [String: [String: Date]]
    }

    private static func encode(_ earned: [AchievementID: [Int: Date]]) -> Data? {
        var wire: [String: [String: Date]] = [:]
        for (id, tiers) in earned {
            wire[id.rawValue] = Dictionary(
                uniqueKeysWithValues: tiers.map { (String($0.key), $0.value) })
        }
        return try? JSONEncoder().encode(Envelope(version: 1, earned: wire))
    }

    private static func decode(_ data: Data?) -> [AchievementID: [Int: Date]]? {
        guard let data, let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        else { return nil }
        var out: [AchievementID: [Int: Date]] = [:]
        for (rawID, tiers) in envelope.earned {
            // Unknown ids (a newer build's feats) drop from the decoded view but
            // survive untouched on the cloud side.
            guard let id = AchievementID(rawValue: rawID) else { continue }
            for (rawTier, date) in tiers {
                guard let tier = Int(rawTier) else { continue }
                out[id, default: [:]][tier] = date
            }
        }
        return out
    }
}
