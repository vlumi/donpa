import Foundation

/// Per-difficulty stats store (clears + best time + career counters), persisted
/// in `UserDefaults` with optional cross-device sync via iCloud KVS (see
/// `CloudStatsStore` / `StatsMerge`). The `ScoreRecord` value type lives in
/// `ScoreRecord.swift`.
@MainActor
public final class Scoreboard: ObservableObject {
    /// THIS device's own records — the source of truth for our counts and best
    /// times. Writes mutate this; it's pushed to the cloud as this device's blob.
    /// The UI reads the merged `displayRecords` via the accessors.
    @Published private(set) var records: [String: ScoreRecord]

    /// Cross-device view: own records merged with every other device's blob (see
    /// `StatsMerge`); equals `records` when sync is off/unavailable. The UI uses this.
    @Published public private(set) var displayRecords: [String: ScoreRecord]

    /// The config whose record was just set, so the scoreboard can highlight that
    /// row; cleared when the next game ends. Not persisted.
    @Published public private(set) var recentRecord: String?

    private let defaults: UserDefaults
    private let key = Scoreboard.localStoreKey
    static let localStoreKey = "donpa.stats.v1"

    /// Owns the iCloud-KVS sync (push / merge / offline cache); nil-cloud → local.
    private let sync: StatsSyncCoordinator

    /// User gate for cross-device sync (pass-through to the coordinator).
    public var syncEnabled: Bool {
        get { sync.syncEnabled }
        set { sync.syncEnabled = newValue }
    }
    /// Sync on AND iCloud reachable — for the status row.
    public var isCloudActive: Bool { sync.isCloudActive }
    /// iCloud reachable (signed in), independent of the sync preference — so the UI
    /// can refuse to enable sync when it couldn't work.
    public var isCloudAvailable: Bool { sync.isCloudAvailable }
    /// Pull + re-push + re-merge from the cloud (call on foreground).
    public func refreshFromCloud() { sync.refreshFromCloud() }
    /// Every device's records keyed by DeviceID (own included, from the local
    /// store) — the "Scores by device" reader. Sync off/offline → own only.
    public func perDeviceRecords() -> [String: [String: ScoreRecord]] {
        sync.perDeviceRecords()
    }
    /// This device's blob key, so the per-device view can mark "this device".
    public var ownDeviceID: String { sync.deviceID }
    /// Whether flipping sync ON right now would clear this device's local records
    /// (a global wipe happened while sync was off) — so the toggle UI can ask first.
    public var enablingSyncWouldWipeLocal: Bool { sync.enablingSyncWouldWipeLocal }

    /// Another live install is writing this device's blob slot — two devices
    /// share one DeviceID (a kept-alive clone). Surfaced so the UI can
    /// suggest the fork; latched until relaunch.
    @Published public private(set) var idCollisionDetected = false

    /// A staged fork's local half: reset the stores whose counters would
    /// double-count if republished under the new id. Called by DeviceFork
    /// BEFORE any Scoreboard exists; never touches the cloud.
    static func forkLocalState(in defaults: UserDefaults) {
        defaults.removeObject(forKey: localStoreKey)
        // The offline cache carries the OLD identity's mine/others split —
        // stale for the new id; the first online refresh rebuilds it.
        defaults.removeObject(forKey: StatsSyncCoordinator.mergedCacheKey)
    }

    public init(
        defaults: UserDefaults = .standard,
        cloud: (any CloudStatsStore)? = nil,
        syncEnabled: Bool = true,
        writerToken: String? = nil
    ) {
        self.defaults = defaults
        // Load own records, but drop them if the local blob predates the reset-epoch
        // floor — the one-off pre-release wipe applies to this device's own store
        // too, not just the cloud (see StatsSyncCoordinator.epochFloor).
        let own = Self.load(from: defaults, key: key)
        records = own
        displayRecords = own
        sync = StatsSyncCoordinator(
            cloud: cloud, deviceID: DeviceID.current(in: defaults), defaults: defaults,
            syncEnabled: syncEnabled, writerToken: writerToken,
            encode: Self.encodeFile, decode: Self.decodeBlob,
            decodeEpoch: Self.decodeEpoch, decodeWriter: Self.decodeWriter)
        sync.onCollision = { [weak self] in self?.idCollisionDetected = true }
        // Wire the coordinator's hooks now that `self` exists; it only calls them
        // from the methods invoked below.
        sync.ownRecords = { [weak self] in self?.records ?? [:] }
        sync.onMerged = { [weak self] merged in self?.displayRecords = merged }
        // On honoring a remote wipe, drop this device's own records (+ persist the
        // empty local store, without re-pushing — the coordinator handles the blob).
        sync.clearOwnRecords = { [weak self] in
            self?.records = [:]
            self?.recentRecord = nil
            self?.persistLocalOnly()
        }
        // Offline launch: project own records over the last cached merge if syncing
        // (own data live, others' sums from the cache — never a frozen snapshot).
        if syncEnabled, let cached = sync.cachedMerge() {
            displayRecords = StatsMerge.offlineMerge(own: own, cached: cached)
        }
        sync.pushAndMerge()
    }

    // Read accessors reflect the cross-device DISPLAY view (own merged with other
    // devices'); writes below mutate this device's OWN `records`.

    public func record(for config: GameConfig) -> ScoreRecord? {
        displayRecords[config.storageKey]
    }

    public func best(for config: GameConfig) -> Int? {
        displayRecords[config.storageKey]?.bestCentiseconds
    }

    public func wins(for config: GameConfig) -> Int {
        displayRecords[config.storageKey]?.wins.total ?? 0
    }

    /// Best progress (0...1), or nil if the config was never finished. A recorded
    /// best TIME means cleared → 100% (more robust than the wins counter, which can
    /// read 0 while a best time survives — see ScoreRecord's tolerant decode); else
    /// the best loss progress.
    public func bestProgress(for config: GameConfig) -> Double? {
        guard let record = displayRecords[config.storageKey] else { return nil }
        if record.bestCentiseconds != nil || record.wins.total > 0 { return 1.0 }
        return record.bestLossProgress
    }

    /// Whether `centiseconds` beats the cross-device best (so a faster time on
    /// another device already counts).
    public func isNewRecord(_ centiseconds: Int, for config: GameConfig) -> Bool {
        guard let best = displayRecords[config.storageKey]?.bestCentiseconds else { return true }
        return centiseconds < best
    }

    /// Record a win's TIMES: store this DEVICE's best/top times and fold in the
    /// mastery signals. The best time is device-owned (kept on our own record
    /// regardless of other devices) with its timestamp; the "new record" the UI
    /// celebrates is still judged against the CROSS-DEVICE best. Returns true if
    /// this beat the cross-device best. The win TALLY lives in
    /// `recordGameOutcome` — a daily clear counts as a win but never submits a
    /// time, so the tallies must not ride the time path.
    @discardableResult
    public func submit(
        _ centiseconds: Int, for config: GameConfig,
        at achievedAt: Date = Date(),
        threeBV: Int? = nil
    ) -> Bool {
        var record = records[config.storageKey] ?? ScoreRecord()
        stampPlayed(&record, at: achievedAt)

        // "New record" is judged against the cross-device best (a faster time on
        // another device already counts); the value is stored device-owned
        // regardless. ONE rule — isNewRecord is the tested source (incl. its
        // ties-don't-count edge), read before this win is folded in below.
        let isCrossDeviceBest = isNewRecord(centiseconds, for: config)
        let time = BestTime(centiseconds: centiseconds, achievedAt: achievedAt)
        // Our OWN best: keep the faster of ours and this clear (independent of others).
        if record.best.map({ centiseconds < $0.centiseconds }) ?? true {
            record.best = time
        }
        record.topTimes.insertTop(time, limit: ScoreRecord.topTimeLimit)
        // The pace window: newest first, capped (the skill-rank raw material) —
        // and the fastest-pace win, kept whole like `best`.
        if let threeBV {
            let win = RecentWin(date: achievedAt, centiseconds: centiseconds, threeBV: threeBV)
            record.recentWins.insert(win, at: 0)
            record.recentWins = Array(record.recentWins.prefix(ScoreRecord.recentWinLimit))
            if win.pace > (record.bestPace?.pace ?? 0) { record.bestPace = win }
        }
        if isCrossDeviceBest { recentRecord = config.storageKey }

        records[config.storageKey] = record
        persist()
        return isCrossDeviceBest
    }

    /// Stamp first/last-played on a record (first set once; last always advances).
    private func stampPlayed(_ record: inout ScoreRecord, at date: Date) {
        if record.firstPlayed == nil { record.firstPlayed = date }
        record.lastPlayed = date
    }

    /// Record a *losing* game's progress. This device's OWN best is always kept up
    /// to date (mirroring `submit`'s device-owned best times — independent of other
    /// devices, so it survives them resetting/leaving); the returned "new best" is
    /// still judged against the cross-device view (100% once anyone cleared it).
    /// A 0% loss records nothing. Don't call on a win — that's `submit`.
    @discardableResult
    public func submitLossProgress(
        _ progress: Double, for config: GameConfig, at date: Date = Date()
    ) -> Bool {
        guard progress > 0 else { return false }
        var record = records[config.storageKey] ?? ScoreRecord()
        let isBest = progress > (bestProgress(for: config) ?? 0)
        let improvesOwn = progress > (record.bestLossProgress ?? 0)
        guard isBest || improvesOwn else { return false }
        if improvesOwn { record.bestLossProgress = progress }
        stampPlayed(&record, at: date)
        records[config.storageKey] = record
        if isBest { recentRecord = config.storageKey }
        persist()
        return isBest
    }

    /// Add an in-game activity DELTA (tiles/flags/time) to the lifetime totals.
    /// Called repeatedly during play (the view model tracks what's flushed, so no
    /// double-count); does NOT touch games-played or outcomes. Empty deltas skipped.
    public func recordActivity(
        for config: GameConfig, tilesOpened: Int, flagsPlaced: Int, playtimeCentiseconds: Int
    ) {
        guard tilesOpened != 0 || flagsPlaced != 0 || playtimeCentiseconds != 0 else { return }
        var record = records[config.storageKey] ?? ScoreRecord()
        record.tilesOpened.add(tilesOpened)
        record.flagsPlaced.add(flagsPlaced)
        record.playtimeCentiseconds.add(playtimeCentiseconds)
        records[config.storageKey] = record
        persist()
    }

    /// Record a finished game's outcome: games-played, win/loss, the mine tally (one
    /// hit on a loss; disarmed count on a win), and the chords used this game.
    /// Owns ALL the outcome tallies — wins included, so a daily clear counts
    /// without submitting a time. `noFlag`/`noChord` are the game-end purity
    /// bits (a resumed game passes them as false); only a won game earns them.
    /// Activity accrues separately via `recordActivity`; best times /
    /// loss-progress via `submit`/`submitLossProgress`.
    public func recordGameOutcome(
        for config: GameConfig, won: Bool, minesHit: Int, minesDisarmed: Int,
        chordsUsed: Int = 0, noFlag: Bool = false, noChord: Bool = false,
        at date: Date = Date()
    ) {
        var record = records[config.storageKey] ?? ScoreRecord()
        record.gamesPlayed.add(1)
        if won {
            record.wins.add(1)
            if noFlag { record.noFlagWins.add(1) }
            if noChord { record.noChordWins.add(1) }
        } else {
            record.losses.add(1)
        }
        record.minesHit.add(minesHit)
        record.minesDisarmed.add(minesDisarmed)
        record.chordsUsed.add(chordsUsed)
        stampPlayed(&record, at: date)
        records[config.storageKey] = record
        persist()
    }

    /// Record a FORCED guess (see `GuessOdds`): the board offered no certainly-safe
    /// cell, the player revealed one anyway, and either survived it or didn't. A
    /// survived guess can also set this device's luckiest-guess record (lowest
    /// survival odds, min-projected across devices at merge).
    public func recordForcedGuess(
        for config: GameConfig, survival: Double, survived: Bool, at date: Date = Date()
    ) {
        var record = records[config.storageKey] ?? ScoreRecord()
        record.forcedGuesses.add(1)
        if survived {
            record.guessesSurvived.add(1)
            let guess = LuckiestGuess(survival: survival, achievedAt: date)
            if record.luckiestGuess.map({ guess < $0 }) ?? true {
                record.luckiestGuess = guess
            }
        }
        records[config.storageKey] = record
        persist()
    }

    /// Global cumulative totals (summed across every config). These are the
    /// player-facing lifetime stats — never a ratio (no win%, which only
    /// discourages); the raw counts stay neutral.
    public var totalWins: Int { displayRecords.values.reduce(0) { $0 + $1.wins.total } }
    public var totalGamesPlayed: Int {
        displayRecords.values.reduce(0) { $0 + $1.gamesPlayed.total }
    }
    public var totalTilesOpened: Int {
        displayRecords.values.reduce(0) { $0 + $1.tilesOpened.total }
    }
    public var totalFlagsPlaced: Int {
        displayRecords.values.reduce(0) { $0 + $1.flagsPlaced.total }
    }
    public var totalMinesHit: Int { displayRecords.values.reduce(0) { $0 + $1.minesHit.total } }
    public var totalMinesDisarmed: Int {
        displayRecords.values.reduce(0) { $0 + $1.minesDisarmed.total }
    }
    public var totalPlaytimeCentiseconds: Int {
        displayRecords.values.reduce(0) { $0 + $1.playtimeCentiseconds.total }
    }
    public var totalForcedGuesses: Int {
        displayRecords.values.reduce(0) { $0 + $1.forcedGuesses.total }
    }
    public var totalGuessesSurvived: Int {
        displayRecords.values.reduce(0) { $0 + $1.guessesSurvived.total }
    }
    /// The longest-odds forced guess survived on any board, across devices.
    public var luckiestGuess: LuckiestGuess? {
        displayRecords.values.compactMap(\.luckiestGuess).min()
    }

    /// Clear the just-set-record highlight. Called when the next game ends.
    public func clearRecentRecord() {
        recentRecord = nil
    }

    /// Clear THIS device's scores — locally AND its contribution to iCloud (delete
    /// its cloud blob). So the shared totals on the player's OTHER devices drop by
    /// this device's amount too. Other devices' own blobs are untouched — a reset
    /// here can't erase another device's history. (When sync is off, this is a
    /// purely local clear; deleting the blob is a no-op since it isn't published.)
    public func reset() {
        sync.deleteOwnBlob()
        records = [:]
        recentRecord = nil
        persist()  // re-publishes an empty blob + re-merges → contributes nothing
    }

    /// GLOBAL wipe across all the player's devices, and it STICKS: bumps the cloud
    /// reset epoch (a tombstone every device honors, so an offline one wipes itself
    /// on return instead of resurrecting), deletes all cloud blobs, and clears this
    /// device. Returns whether the global tombstone was planted — false means sync
    /// was off or iCloud unreachable, so per the sync-scoped rule this fell back to
    /// a LOCAL-only clear (the cloud was deliberately left untouched).
    @discardableResult
    public func wipeAllSynced() -> Bool {
        let global = sync.wipeAllSynced()
        records = [:]
        recentRecord = nil
        if global {
            persistLocalOnly()  // epoch already bumped; coordinator owns the blob
            sync.refresh()
        } else {
            reset()  // local clear (also removes our own blob if one somehow exists)
        }
        return global
    }

    /// Persist own records locally (stamped with the current epoch), then push +
    /// re-merge via the coordinator. Every score-write path funnels here.
    private func persist() {
        persistLocalOnly()
        sync.pushAndMerge()
    }

    /// Write own records to the local store only (stamped with the honored epoch),
    /// without touching the cloud. Used when the coordinator already owns the cloud
    /// side (honoring a remote wipe, or after a global wipe bumped the epoch).
    private func persistLocalOnly() {
        if let data = Self.encodeFile(records, epoch: sync.honoredEpoch) {
            defaults.set(data, forKey: key)
        }
    }
}
