import Foundation

/// Persists in-progress games, one file per config, in a `saves/` directory —
/// the directory listing IS the index. Writes are atomic; loads are tolerant
/// (missing, unreadable, wrong-version, or geometry-stale files yield nil).
public struct SaveStore {
    private let directory: URL
    private let fileManager: FileManager

    public init(directory: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = directory.appendingPathComponent("saves", isDirectory: true)
        try? fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
        // Drop the obsolete pre-per-config single-slot save (no migration by design).
        try? fileManager.removeItem(at: directory.appendingPathComponent("currentGame.json"))
    }

    /// Cached: resolving hits the filesystem, and callers construct stores frequently.
    private static let appSupportDirectory: URL = {
        let fm = FileManager.default
        return
            (try? fm.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
    }()

    public static func appSupport(fileManager: FileManager = .default) -> SaveStore {
        SaveStore(directory: appSupportDirectory, fileManager: fileManager)
    }

    /// A fresh store in a unique temp directory — UI-test isolation (`-uitest-clean`).
    public static func ephemeral(fileManager: FileManager = .default) -> SaveStore {
        let dir = fileManager.temporaryDirectory
            .appendingPathComponent("donpa-uitest-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return SaveStore(directory: dir, fileManager: fileManager)
    }

    public static var isUITestCleanLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-clean")
    }

    /// `storageKey` is already stable and versioned; non-alphanumerics map to `_`
    /// for a filename-safe name.
    private func url(for config: GameConfig) -> URL {
        let safe = String(config.storageKey.map { $0.isLetter || $0.isNumber ? $0 : "_" })
        return directory.appendingPathComponent("save-\(safe).json")
    }

    /// The tiny sidecar summary next to a save: listing saves by decoding the full
    /// files was a ~1s main-thread stall (an XXXL save is ~2MB of JSON). Written and
    /// removed by the same code paths as the main file, so there's no index to drift.
    private func summaryURL(forMainFile mainURL: URL) -> URL {
        let name = mainURL.lastPathComponent.replacingOccurrences(
            of: "save-", with: "summary-")
        return mainURL.deletingLastPathComponent().appendingPathComponent(name)
    }

    private func summaryURL(for config: GameConfig) -> URL {
        summaryURL(forMainFile: url(for: config))
    }

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

    /// Container magic, then a zlib-deflated JSON payload. The digit versions the
    /// CONTAINER format (the JSON inside carries its own schema version). No
    /// plain-JSON fallback: the format never shipped uncompressed.
    private static let compressedMagic = Data("DONPAZ1\n".utf8)

    /// nil on a compression failure — the caller skips the write, leaving the
    /// previous good save intact.
    private func pack(_ data: Data) -> Data? {
        guard let compressed = try? (data as NSData).compressed(using: .zlib) as Data
        else { return nil }
        return Self.compressedMagic + compressed
    }

    private func unpack(_ data: Data) -> Data? {
        guard data.starts(with: Self.compressedMagic) else { return nil }
        let payload = Data(data.dropFirst(Self.compressedMagic.count))
        return try? (payload as NSData).decompressed(using: .zlib) as Data
    }

    private func writeSummary(_ summary: SaveSummary) {
        guard let data = try? JSONEncoder().encode(summary) else { return }
        try? data.write(to: summaryURL(for: summary.config), options: [.atomic])
    }

    /// nil if none / unreadable / unsupported version / geometry-stale.
    public func load(config: GameConfig) -> GameSnapshot? {
        decode(try? Data(contentsOf: url(for: config)))
    }

    /// Every live saved game, newest-played first.
    public func all() -> [GameSnapshot] {
        savedURLs()
            .compactMap { decode(try? Data(contentsOf: $0)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Lightweight view of one saved game for lists and cues, WITHOUT the board's
    /// coord sets (an XXXL snapshot holds ~1M coords; a list of those is a memory
    /// trap). Codable: persisted as the sidecar file.
    public struct SaveSummary: Equatable, Sendable, Codable {
        public let config: GameConfig
        public let elapsedCentiseconds: Int
        public let revealedSafeCount: Int
        public let updatedAt: Date

        public var progressPercent: Int {
            let safe = max(1, config.width * config.height - config.mineCount)
            return Int((Double(revealedSafeCount) / Double(safe) * 100).rounded())
        }
    }

    /// Summaries of every live saved game, newest-played first. A save missing its
    /// sidecar (a pre-sidecar build's) falls back to a full decode and HEALS by
    /// writing one, so the slow path runs at most once per save.
    public func summaries() -> [SaveSummary] {
        savedURLs()
            .compactMap { summary(forMainFile: $0) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func summary(forMainFile mainURL: URL) -> SaveSummary? {
        // Container check FIRST — a sidecar must never vouch for a main file that
        // can't load (phantom rows whose resume did nothing). Mapped read: the
        // prefix check touches one page.
        guard let raw = try? Data(contentsOf: mainURL, options: .mappedIfSafe) else {
            return nil
        }
        guard raw.starts(with: Data("DONPAZ".utf8)) else {
            // Not our container at all — a dead relic; drop it and its sidecar.
            try? fileManager.removeItem(at: mainURL)
            try? fileManager.removeItem(at: summaryURL(forMainFile: mainURL))
            return nil
        }
        guard raw.starts(with: Self.compressedMagic) else {
            // Our container, newer version (a future build's save): hide, do NOT delete.
            return nil
        }
        if let data = try? Data(contentsOf: summaryURL(forMainFile: mainURL)),
            let summary = try? JSONDecoder().decode(SaveSummary.self, from: data)
        {
            return summary
        }
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

    /// Tolerant decode. Rejects non-`.playing` snapshots here rather than relying on
    /// them being cleared everywhere: a won/lost snapshot that slipped to disk (e.g.
    /// an app-exit save after the result) must never resurface as a "Continue".
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
