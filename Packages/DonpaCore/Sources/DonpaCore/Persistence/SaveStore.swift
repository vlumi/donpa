import Foundation

/// Persists in-progress games — **one save per config** — as files in a `saves/`
/// directory. The directory listing IS the index: no separate index file to keep in
/// sync, discarding a game is one `unlink`, and resuming loads only the one file.
///
/// Writes are atomic (a crash mid-save leaves the previous good save intact). Loads
/// are tolerant: a missing, unreadable, wrong-version, or geometry-stale file yields
/// nil rather than throwing. Keyed by `GameConfig.storageKey`, sanitized to a
/// filesystem-safe filename.
public struct SaveStore {
    private let directory: URL
    private let fileManager: FileManager

    public init(directory: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = directory.appendingPathComponent("saves", isDirectory: true)
        try? fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
        // One-time cleanup: the old single-slot save is obsolete under per-config
        // saves. Discard it (decided: no migration — one in-progress game lost at the
        // upgrade boundary is acceptable) so it doesn't linger unreadable.
        try? fileManager.removeItem(at: directory.appendingPathComponent("currentGame.json"))
    }

    /// The Application Support directory, resolved ONCE per process. Resolving it hits
    /// the filesystem; callers construct the store frequently, so cache it.
    private static let appSupportDirectory: URL = {
        let fm = FileManager.default
        return
            (try? fm.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
    }()

    /// The production store, in Application Support (temp dir as a last resort).
    public static func appSupport(fileManager: FileManager = .default) -> SaveStore {
        SaveStore(directory: appSupportDirectory, fileManager: fileManager)
    }

    /// A fresh, empty store in a unique temp directory, never touching the real
    /// Application Support store. Used by UI tests (`-uitest-clean`) for isolation.
    public static func ephemeral(fileManager: FileManager = .default) -> SaveStore {
        let dir = fileManager.temporaryDirectory
            .appendingPathComponent("donpa-uitest-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return SaveStore(directory: dir, fileManager: fileManager)
    }

    /// Whether the app was launched for a clean UI-test run.
    public static var isUITestCleanLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-clean")
    }

    /// The file for a config's save. `storageKey` is already a stable, versioned key
    /// (`v2|grid|flat|16x16|m31`); its `|` and `x` etc. are kept filename-safe by
    /// mapping any non-alphanumeric to `_`.
    private func url(for config: GameConfig) -> URL {
        let safe = String(config.storageKey.map { $0.isLetter || $0.isNumber ? $0 : "_" })
        return directory.appendingPathComponent("save-\(safe).json")
    }

    /// The tiny sidecar summary next to a save (~150 bytes). Listing dozens of saves
    /// by decoding the FULL files was a ~1s main-thread stall (an XXXL save is ~2MB
    /// of JSON; 50 games ≈ 9MB parsed per Home/New Game open); the sidecars make it
    /// milliseconds. Written and removed by the SAME code paths as the main file, so
    /// there's no central index to drift — and `summaries()` self-heals a missing
    /// one from the main file anyway.
    private func summaryURL(forMainFile mainURL: URL) -> URL {
        let name = mainURL.lastPathComponent.replacingOccurrences(
            of: "save-", with: "summary-")
        return mainURL.deletingLastPathComponent().appendingPathComponent(name)
    }

    private func summaryURL(for config: GameConfig) -> URL {
        summaryURL(forMainFile: url(for: config))
    }

    /// Atomically write the snapshot to its config's file (+ its sidecar summary);
    /// failures are swallowed. The payload is zlib-compressed (see `pack`).
    public func save(_ snapshot: GameSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot),
            let packed = pack(data)
        else { return }
        try? packed.write(to: url(for: snapshot.config), options: [.atomic])
        writeSummary(
            SaveSummary(
                config: snapshot.config, elapsedCentiseconds: snapshot.elapsedCentiseconds,
                revealedSafeCount: snapshot.revealedSafeCount, updatedAt: snapshot.updatedAt))
    }

    // MARK: Compression

    /// Every save starts with this magic, then a zlib-deflated JSON payload. The
    /// digit versions the CONTAINER format (the JSON inside carries its own schema
    /// version). No plain-JSON fallback: the format never shipped uncompressed, so
    /// anything without the magic is rejected like any other unreadable file.
    private static let compressedMagic = Data("DONPAZ1\n".utf8)

    /// zlib-deflate the payload. A fresh XXXL save (random mine coords, high
    /// entropy) measures ~2.6× smaller; the ratio improves as the board is played,
    /// since the growing `revealed` set is contiguous regions — and plain, a
    /// well-cleared XXXL save would head toward ~10MB. nil on a compression
    /// failure — the caller skips the write, leaving the previous good save intact.
    private func pack(_ data: Data) -> Data? {
        guard let compressed = try? (data as NSData).compressed(using: .zlib) as Data
        else { return nil }
        return Self.compressedMagic + compressed
    }

    /// Undo `pack`: nil unless the magic is present and the payload inflates.
    private func unpack(_ data: Data) -> Data? {
        guard data.starts(with: Self.compressedMagic) else { return nil }
        let payload = Data(data.dropFirst(Self.compressedMagic.count))
        return try? (payload as NSData).decompressed(using: .zlib) as Data
    }

    private func writeSummary(_ summary: SaveSummary) {
        guard let data = try? JSONEncoder().encode(summary) else { return }
        try? data.write(to: summaryURL(for: summary.config), options: [.atomic])
    }

    /// The saved snapshot for a config, or nil if none / unreadable / unsupported
    /// version / geometry-stale (a size/density retune between builds).
    public func load(config: GameConfig) -> GameSnapshot? {
        decode(try? Data(contentsOf: url(for: config)))
    }

    /// Every live saved game, newest-played first — the in-progress list.
    public func all() -> [GameSnapshot] {
        savedURLs()
            .compactMap { decode(try? Data(contentsOf: $0)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// A lightweight view of one saved game, for lists and cues — everything the
    /// Home card / New Game dots need, WITHOUT retaining the board's coord sets
    /// (an XXXL snapshot holds ~1M coords; a list of those is a memory trap).
    /// Codable: persisted as the sidecar summary file next to each save.
    public struct SaveSummary: Equatable, Sendable, Codable {
        public let config: GameConfig
        public let elapsedCentiseconds: Int
        public let revealedSafeCount: Int
        public let updatedAt: Date

        /// Whole-percent board progress (revealed safe cells over the config's
        /// safe-cell count).
        public var progressPercent: Int {
            let safe = max(1, config.width * config.height - config.mineCount)
            return Int((Double(revealedSafeCount) / Double(safe) * 100).rounded())
        }
    }

    /// Summaries of every live saved game, newest-played first — the fast path for
    /// lists and cues. Reads each save's tiny sidecar; a save missing its sidecar
    /// (e.g. written by a pre-sidecar build) falls back to a full decode and HEALS
    /// by writing the sidecar, so the slow path runs at most once per save.
    public func summaries() -> [SaveSummary] {
        savedURLs()
            .compactMap { summary(forMainFile: $0) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func summary(forMainFile mainURL: URL) -> SaveSummary? {
        // Container check FIRST — a sidecar must never vouch for a main file that
        // can't load (that made unreadable saves list as phantom rows whose resume
        // silently did nothing). Mapped read: the prefix check touches one page.
        guard let raw = try? Data(contentsOf: mainURL, options: .mappedIfSafe) else {
            return nil
        }
        guard raw.starts(with: Data("DONPAZ".utf8)) else {
            // Not even our container family: a dead relic (pre-compression build,
            // or corruption). Drop it and its sidecar so it stops haunting lists.
            try? fileManager.removeItem(at: mainURL)
            try? fileManager.removeItem(at: summaryURL(forMainFile: mainURL))
            return nil
        }
        guard raw.starts(with: Self.compressedMagic) else {
            // Our container, DIFFERENT version: a future build's save seen by a
            // downgraded app. Hide it, but do NOT delete — that's their data.
            return nil
        }
        if let data = try? Data(contentsOf: summaryURL(forMainFile: mainURL)),
            let summary = try? JSONDecoder().decode(SaveSummary.self, from: data)
        {
            return summary
        }
        // No/unreadable sidecar: derive from the full save (same gating as `all()`)
        // and heal, so the next listing takes the fast path.
        guard let snapshot = decode(raw) else { return nil }
        let summary = SaveSummary(
            config: snapshot.config, elapsedCentiseconds: snapshot.elapsedCentiseconds,
            revealedSafeCount: snapshot.revealedSafeCount, updatedAt: snapshot.updatedAt)
        writeSummary(summary)
        return summary
    }

    public func hasSave(config: GameConfig) -> Bool {
        fileManager.fileExists(atPath: url(for: config).path)
    }

    /// Remove a config's save + its sidecar (on finish / new game on it / discard).
    public func clear(config: GameConfig) {
        try? fileManager.removeItem(at: url(for: config))
        try? fileManager.removeItem(at: summaryURL(for: config))
    }

    // MARK: Internals

    private func savedURLs() -> [URL] {
        let files =
            (try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("save-") }
    }

    /// Shared tolerant decode: version-gated, geometry-checked, and in-progress only.
    /// A save is only resumable while the game is still playable — a won/lost snapshot
    /// that slipped to disk (e.g. an app-exit save fired after the result) must never
    /// resurface as a "Continue", so it's rejected here rather than relied on being
    /// cleared everywhere it could be written. Inflates compressed payloads first
    /// (see `unpack`). See `load`.
    private func decode(_ data: Data?) -> GameSnapshot? {
        guard let raw = data, let data = unpack(raw) else { return nil }
        guard
            let snapshot = try? JSONDecoder().decode(GameSnapshot.self, from: data),
            snapshot.version <= GameSnapshot.currentVersion,
            snapshot.status == .playing,
            snapshot.isConsistent
        else { return nil }
        return snapshot.migrated()
    }
}
