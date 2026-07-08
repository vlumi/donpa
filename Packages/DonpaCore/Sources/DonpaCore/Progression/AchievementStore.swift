import Foundation

/// The earned-feat record (A3 of the progression spec): id × tier → the date
/// first earned. Local-first (UserDefaults), synced as a per-device KVS blob
/// whose merge is a pure UNION with the EARLIEST date winning — achievements
/// never delete, so there are no tombstones, no LWW, and deliberately **no
/// reset-epoch: feats are permanent** (the stats wipe never touches this store;
/// hidden feats can't be re-derived and Game Center can't un-report).
///
/// Derivable feats are STAMPED here when first observed (see `reconcile`), so
/// dates stay stable and the future Game Center reporter fires once per tier.
@MainActor
public final class AchievementStore: ObservableObject {
    /// Earned tiers per feat: tier (1-based) → date first earned. One-shot
    /// feats live at tier 1.
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

    /// When a tier was first earned (anywhere), or nil.
    public func firstEarned(_ id: AchievementID, tier: Int = 1) -> Date? {
        earned[id]?[tier]
    }

    // MARK: Writes

    /// Stamp one feat tier; false if it was already earned (a feat only ever
    /// fires once — the celebration and the future GC report key off `true`).
    /// An EARLIER date still lowers the stamp (the union invariant: the first
    /// earn anywhere wins, whichever order the devices sync in).
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

    /// Stamp everything the records prove that the store doesn't hold yet —
    /// the retroactive pass (veterans on first launch, cloud restores). Returns
    /// the fresh stamps, oldest feats first, for the celebration queue.
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

    /// Follow the sync toggle: on turns publishing on and merges what's there;
    /// off removes this device's slot (local earnings stay — permanence).
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

    /// Union every device's blob into the local set (earliest date per tier
    /// wins), and re-publish when the union taught us something new.
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

    /// This device's blob is the full known union — idempotent under the union
    /// merge, and it converges the fleet faster than own-earnings-only would.
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
    /// throughout (Int-keyed Codable dictionaries encode as arrays), unknown
    /// ids tolerated (a future version's feats survive a round-trip here).
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
            // Unknown ids (a newer build's feats) are dropped from the DECODED
            // view but survive on the cloud side untouched.
            guard let id = AchievementID(rawValue: rawID) else { continue }
            for (rawTier, date) in tiers {
                guard let tier = Int(rawTier) else { continue }
                out[id, default: [:]][tier] = date
            }
        }
        return out
    }
}
