import Foundation

/// Persists this device's daily-challenge days and projects the cross-device
/// view — the scoreboard's shape in miniature: own records are the source of
/// truth, one blob per device under the sync gate, merge on read.
@MainActor
public final class DailyStore: ObservableObject {
    @Published public private(set) var displayRecords: [String: DailyDayRecord] = [:]

    private(set) var records: [String: DailyDayRecord] = [:]
    private let defaults: UserDefaults
    private let key = DailyStore.localStoreKey
    static let localStoreKey = "donpa.daily.v1"

    /// A staged fork's local half (see DeviceFork): per-day attempt counters
    /// would double-count if republished under a new id, so the local store
    /// resets — the merged view recovers every day from the old blob.
    static func forkLocalState(in defaults: UserDefaults) {
        defaults.removeObject(forKey: localStoreKey)
    }
    private let cloud: CloudDailyStore?
    private let deviceID: String

    public var syncEnabled: Bool {
        didSet {
            guard syncEnabled != oldValue else { return }
            if syncEnabled { pushOwnBlob() } else { cloud?.deleteOwnBlob(deviceID: deviceID) }
            remerge()
        }
    }

    public init(
        cloud: CloudDailyStore?, deviceID: String, syncEnabled: Bool,
        defaults: UserDefaults = .standard
    ) {
        self.cloud = cloud
        self.deviceID = deviceID
        self.syncEnabled = syncEnabled
        self.defaults = defaults
        records = Self.decode(defaults.data(forKey: key)) ?? [:]
        cloud?.onExternalChange = { [weak self] in self?.remerge() }
        if syncEnabled { pushOwnBlob() }
        remerge()
    }

    /// One finished attempt (won or lost) — the only thing that mutates a day.
    public struct Attempt {
        public let won: Bool
        public let centiseconds: Int
        public let threeBV: Int?
        public let progress: Double
        /// Completed ON the day itself — the only thing streaks count.
        public let live: Bool

        public init(won: Bool, centiseconds: Int, threeBV: Int?, progress: Double, live: Bool) {
            self.won = won
            self.centiseconds = centiseconds
            self.threeBV = threeBV
            self.progress = progress
            self.live = live
        }
    }

    /// The ordinal is this device's attempt sequence, captured when a new
    /// best lands (stored, undisplayed until device attribution exists).
    public func recordAttempt(dateKey: String, _ attempt: Attempt) {
        var day = records[dateKey] ?? DailyDayRecord()
        day.attempts.add(1)
        day.playedLive = day.playedLive || attempt.live
        if attempt.won {
            if attempt.centiseconds < (day.best?.centiseconds ?? .max) {
                day.best = DailyDayRecord.Best(
                    centiseconds: attempt.centiseconds, threeBV: attempt.threeBV ?? 0,
                    attemptOrdinal: day.attempts.mine)
            }
        } else {
            day.bestProgress = max(day.bestProgress ?? 0, attempt.progress)
        }
        records[dateKey] = day
        persist()
        pushOwnBlob()
        remerge()
    }

    /// Days played ON the day itself — the only thing streaks count
    /// (calendar replays of past days never repair a streak).
    public var playedDays: Set<String> {
        Set(displayRecords.filter(\.value.playedLive).keys)
    }

    public func currentStreak(today: String = DailyChallenge.dateKey()) -> Int {
        DailyMerge.currentStreak(playedDays: playedDays, today: today)
    }

    /// The career rollup for the Service Record's "Daily orders" segment.
    /// Played counts any attempted day, replays included — the day was faced;
    /// only the streaks insist on live play.
    public struct Career: Equatable, Sendable {
        public let played: Int
        public let cleared: Int
        public let currentStreak: Int
        public let longestStreak: Int
    }

    public var career: Career {
        Career(
            played: displayRecords.count,
            cleared: displayRecords.values.filter(\.cleared).count,
            currentStreak: currentStreak(),
            longestStreak: longestStreak)
    }

    public var longestStreak: Int {
        DailyMerge.longestStreak(playedDays: playedDays)
    }

    private func remerge() {
        let others = (cloud?.readAllBlobs() ?? [:])
            .filter { $0.key != deviceID }
            .compactMap { Self.decode($0.value) }
        displayRecords = DailyMerge.merged(own: records, others: others)
    }

    private func persist() {
        if let data = Self.encode(records) { defaults.set(data, forKey: key) }
    }

    private func pushOwnBlob() {
        guard syncEnabled, let cloud, cloud.isAvailable,
            let data = Self.encode(records)
        else { return }
        cloud.writeOwnBlob(data, deviceID: deviceID)
    }

    private struct File: Codable {
        var version: Int
        var records: [String: DailyDayRecord]
    }

    static let currentVersion = 1

    static func encode(_ records: [String: DailyDayRecord]) -> Data? {
        guard let json = try? JSONEncoder().encode(File(version: currentVersion, records: records))
        else { return nil }
        return (try? (json as NSData).compressed(using: .zlib) as Data) ?? json
    }

    static func decode(_ data: Data?) -> [String: DailyDayRecord]? {
        guard var data else { return nil }
        if data.first != UInt8(ascii: "{") {
            guard let out = try? (data as NSData).decompressed(using: .zlib) as Data else {
                return nil
            }
            data = out
        }
        guard let file = try? JSONDecoder().decode(File.self, from: data),
            file.version <= currentVersion
        else { return nil }
        return file.records
    }
}
