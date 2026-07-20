import Foundation

/// Owns the iCloud-KVS side of the scoreboard: pushing this device's blob,
/// merging every device's blob for display (`StatsMerge`), and caching the merge
/// so combined totals survive going offline. `Scoreboard` keeps the local store +
/// score API and delegates all sync here.
///
/// The coordinator reads this device's own records via `ownRecords` and publishes
/// the merged result via `onMerged` — so it never owns the records, just the
/// transport + merge.
@MainActor
final class StatsSyncCoordinator {
    private let cloud: (any CloudStatsStore)?
    /// This device's blob key — readable so the per-device view can mark
    /// which table is "this device".
    let deviceID: String
    private let defaults: UserDefaults
    /// Cache of the last merge, persisted so totals survive offline rather than
    /// collapsing to own-only then jumping back on reconnect.
    private let mergedKey = StatsSyncCoordinator.mergedCacheKey
    static let mergedCacheKey = "donpa.stats.merged.v1"
    /// The highest reset epoch this device has honored (persisted). A cloud epoch
    /// greater than this means a wipe happened elsewhere that we haven't applied.
    private let honoredEpochKey = "donpa.stats.resetEpoch.honored"
    /// Set when a blob delete had to be dropped because iCloud was unreachable, so
    /// it can be replayed instead of leaking a ghost blob.
    private let pendingDeleteKey = "donpa.stats.pendingBlobDelete"

    /// Read this device's own records (the source pushed + merged). Set by the
    /// owner after init, once `self` exists.
    var ownRecords: () -> [String: ScoreRecord] = { [:] }
    /// Publish the merged (or own-only) display. Set by the owner after init.
    var onMerged: ([String: ScoreRecord]) -> Void = { _ in }
    /// Clear this device's OWN local records (on honoring a remote wipe). Set by the
    /// owner; the coordinator never owns the records, so it asks the owner to drop
    /// them. Called before the subsequent re-merge.
    var clearOwnRecords: () -> Void = {}
    /// Encode/decode a records blob in the Scoreboard's persistence format. Encoding
    /// stamps the current reset epoch into the blob so readers can reject stale ones.
    private let encode: ([String: ScoreRecord], Int, String?) -> Data?
    private let decode: (Data) -> [String: ScoreRecord]
    private let decodeWriter: (Data) -> String?
    /// This install's blob-write stamp (the install marker) — how two live
    /// installs sharing one DeviceID notice each other. nil = don't stamp.
    private let writerToken: String?
    /// Fired once when another install's stamp shows up in OUR slot.
    var onCollision: () -> Void = {}
    private var collisionReported = false
    /// Read just the reset epoch a blob was stamped with (0 if none).
    private let decodeEpoch: (Data) -> Int

    /// User gate. Off → cloud never read/written (own-only display); flipping it
    /// re-publishes (on) or removes this device's blob + shows own-only (off).
    var syncEnabled: Bool {
        didSet {
            guard syncEnabled != oldValue else { return }
            if syncEnabled {
                pushAndMerge()
            } else {
                deleteOwnBlob()  // or remember to, if offline (replayed later)
                refresh()
            }
        }
    }

    /// Whether flipping sync ON right now would clear this device's local records:
    /// a global wipe happened while sync was off (the cloud epoch is ahead of what
    /// we've honored) and there is local data to lose. Read-only — lets the UI ask
    /// before enabling instead of silently honoring the tombstone.
    var enablingSyncWouldWipeLocal: Bool {
        guard !syncEnabled, let cloud, cloud.isAvailable else { return false }
        return cloud.readResetEpoch() > honoredEpoch && !ownRecords().isEmpty
    }

    /// Sync on AND iCloud reachable — for the status row.
    var isCloudActive: Bool { syncEnabled && (cloud?.isAvailable ?? false) }

    /// Whether iCloud is reachable at all (signed in), independent of the sync
    /// preference — so the UI can refuse to enable sync when it couldn't work.
    var isCloudAvailable: Bool { cloud?.isAvailable ?? false }

    init(
        cloud: (any CloudStatsStore)?,
        deviceID: String,
        defaults: UserDefaults,
        syncEnabled: Bool,
        writerToken: String? = nil,
        encode: @escaping ([String: ScoreRecord], Int, String?) -> Data?,
        decode: @escaping (Data) -> [String: ScoreRecord],
        decodeEpoch: @escaping (Data) -> Int,
        decodeWriter: @escaping (Data) -> String?
    ) {
        self.cloud = cloud
        self.deviceID = deviceID
        self.defaults = defaults
        self.syncEnabled = syncEnabled
        self.writerToken = writerToken
        self.encode = encode
        self.decode = decode
        self.decodeEpoch = decodeEpoch
        self.decodeWriter = decodeWriter
        self.cloud?.onExternalChange = { [weak self] in self?.refresh() }
    }

    /// The reset generation this build ships at. Floored to 1 so ALL pre-upgrade
    /// data (blobs/records stamped epoch 0 or unstamped) is below the current epoch
    /// and ignored everywhere — an automatic one-time reset on upgrade, riding the
    /// same tombstone machinery (consistent with the size/difficulty rebalance that
    /// already orphaned old scores). A manual wipe bumps past this to 2, 3, ….
    static let epochFloor = 1

    /// The epoch this device has honored so far, never below the ship floor.
    var honoredEpoch: Int { max(Self.epochFloor, defaults.integer(forKey: honoredEpochKey)) }

    /// The cached merge, or nil if none yet — lets a caller show last-known totals
    /// on an offline launch. A cache stamped below the honored epoch is pre-wipe /
    /// pre-floor data: showing it would resurrect wiped stats on an offline launch.
    func cachedMerge() -> [String: ScoreRecord]? {
        guard let data = defaults.data(forKey: mergedKey) else { return nil }
        guard decodeEpoch(data) >= honoredEpoch else { return nil }
        return decode(data)
    }

    /// Push this device's blob (stamped with the current epoch), then re-merge.
    /// No-op on cloud when sync off / unavailable (still refreshes the display).
    func pushAndMerge() {
        if syncEnabled, let cloud, cloud.isAvailable,
            let data = encode(ownRecords(), honoredEpoch, writerToken)
        {
            // Look before overwriting: a foreign stamp in our slot means a
            // live clone wrote it — flag it even though the write proceeds
            // (last-writer-wins is unchanged; the fork is the real fix).
            detectCollision(ownSlot: cloud.readAllBlobs()[deviceID])
            cloud.writeOwnBlob(data, deviceID: deviceID)
        }
        refresh()
    }

    /// A foreign install stamp in OUR blob slot = two live installs share
    /// this DeviceID. Old-build blobs carry no stamp and stay silent.
    private func detectCollision(ownSlot: Data?) {
        guard !collisionReported, let token = writerToken, let own = ownSlot,
            let writer = decodeWriter(own), writer != token
        else { return }
        collisionReported = true
        onCollision()
    }

    /// Remove this device's cloud blob (on reset / sync-off), so it stops
    /// contributing to other devices' totals — or REMEMBER to, if iCloud is
    /// unreachable right now: a silently-dropped delete leaves a ghost blob other
    /// devices keep counting (forever, if sync stays off). The pending flag is
    /// replayed on the next reachable refresh.
    func deleteOwnBlob() {
        if let cloud, cloud.isAvailable {
            cloud.deleteOwnBlob(deviceID: deviceID)
            defaults.removeObject(forKey: pendingDeleteKey)
        } else {
            defaults.set(true, forKey: pendingDeleteKey)
        }
    }

    /// Replay a dropped blob delete once the cloud is reachable. With sync back ON
    /// the next push overwrites the blob anyway, so the flag just clears.
    private func replayPendingDeleteIfNeeded() {
        guard defaults.bool(forKey: pendingDeleteKey), let cloud, cloud.isAvailable else {
            return
        }
        if !syncEnabled { cloud.deleteOwnBlob(deviceID: deviceID) }
        defaults.removeObject(forKey: pendingDeleteKey)
    }

    /// GLOBAL wipe: bump the cloud reset epoch, delete every visible blob, and clear
    /// the local cache. The caller clears this device's own records. Other devices
    /// (including any offline now) honor the new epoch on their next read and wipe
    /// themselves — so the erase sticks. No-op when sync off / unreachable (the
    /// caller falls back to a local-only reset per the sync-scoped wipe rule).
    /// Returns true if the global tombstone was actually planted.
    @discardableResult
    func wipeAllSynced() -> Bool {
        guard syncEnabled, let cloud, cloud.isAvailable else { return false }
        let next = max(honoredEpoch, cloud.readResetEpoch()) + 1
        // Record our honored epoch BEFORE touching the cloud. Writing the epoch/
        // deleting blobs fires external-change notifications that re-enter refresh()
        // on THIS device synchronously; if honored were still the old value it'd read
        // the new cloud epoch as a "remote wipe" and recurse. Set it first so the
        // re-entrant refresh sees cloudEpoch == honored and stops.
        defaults.set(next, forKey: honoredEpochKey)
        defaults.removeObject(forKey: mergedKey)
        cloud.writeResetEpoch(next)
        cloud.deleteAllBlobs()
        return true
    }

    /// Pull, RE-PUSH, and re-merge (call on foreground): pushing here propagates
    /// changes made while offline (a reset, new scores) on reconnect, instead of
    /// waiting for the next local write. Also replays any dropped blob delete.
    /// Otherwise a no-op when sync off / unavailable.
    func refreshFromCloud() {
        replayPendingDeleteIfNeeded()
        guard syncEnabled, let cloud, cloud.isAvailable else { return }
        cloud.synchronize()
        pushAndMerge()
    }

    /// Recompute the display = own merged with other devices' blobs, and cache it.
    /// - sync OFF: own-only, drop the cache.
    /// - sync ON but unreachable (offline): project FRESH own records over the
    ///   cached merge, so offline play/resets show immediately (never freeze at the
    ///   snapshot), and refresh the cache so an offline relaunch matches.
    /// - sync ON + reachable: honor any newer reset epoch (self-wipe), then re-merge.
    func refresh() {
        replayPendingDeleteIfNeeded()
        guard syncEnabled else {
            onMerged(ownRecords())
            defaults.removeObject(forKey: mergedKey)
            return
        }
        guard let cloud, cloud.isAvailable else {
            let display =
                cachedMerge().map { StatsMerge.offlineMerge(own: ownRecords(), cached: $0) }
                ?? ownRecords()
            onMerged(display)
            // Refresh (or epoch-upgrade) an existing cache; don't mint one offline.
            if defaults.data(forKey: mergedKey) != nil,
                let data = encode(display, honoredEpoch, nil)
            {
                defaults.set(data, forKey: mergedKey)
            }
            return
        }
        // A wipe elsewhere bumped the epoch past what we've honored: this device
        // missed it (or was offline), so wipe ourselves — drop own records, delete
        // our now-stale blob, clear the cache — then adopt the new epoch. An offline
        // device that stored scores meanwhile loses them here; that's the point.
        let cloudEpoch = cloud.readResetEpoch()
        if cloudEpoch > honoredEpoch {
            clearOwnRecords()
            cloud.deleteOwnBlob(deviceID: deviceID)
            defaults.removeObject(forKey: mergedKey)
            defaults.set(cloudEpoch, forKey: honoredEpochKey)
        }
        let epoch = honoredEpoch
        let all = cloud.readAllBlobs()
        detectCollision(ownSlot: all[deviceID])
        var others: [String: [String: ScoreRecord]] = [:]
        for (id, data) in all where id != deviceID {
            // Reject blobs stamped below the current epoch: a returning offline
            // device's pre-wipe blob must not merge in even briefly (belt-and-
            // suspenders over its own self-wipe). Tolerant per-entry decode within.
            guard decodeEpoch(data) >= epoch else { continue }
            others[id] = decode(data)
        }
        let merged = StatsMerge.merge(mine: ownRecords(), others: others)
        onMerged(merged)
        if let data = encode(merged, epoch, nil) { defaults.set(data, forKey: mergedKey) }
    }

    /// Every device's records keyed by its DeviceID — the "Scores by device"
    /// reader. Own table comes from the LOCAL store (fresher than its blob);
    /// the rest from their epoch-valid blobs. Sync off or offline → own only.
    func perDeviceRecords() -> [String: [String: ScoreRecord]] {
        var tables = [deviceID: ownRecords()]
        guard syncEnabled, let cloud, cloud.isAvailable else { return tables }
        let epoch = honoredEpoch
        for (id, data) in cloud.readAllBlobs() where id != deviceID {
            guard decodeEpoch(data) >= epoch else { continue }
            tables[id] = decode(data)
        }
        return tables
    }
}
