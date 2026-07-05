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

    /// Atomically write the snapshot to its config's file; failures are swallowed.
    public func save(_ snapshot: GameSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url(for: snapshot.config), options: [.atomic])
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

    /// The most-recently-played saved game, for auto-resume. nil if there are none.
    public func latest() -> GameSnapshot? { all().first }

    public func hasSave(config: GameConfig) -> Bool {
        fileManager.fileExists(atPath: url(for: config).path)
    }

    /// Remove a config's save (on finish / new game on it / manual discard).
    public func clear(config: GameConfig) {
        try? fileManager.removeItem(at: url(for: config))
    }

    // MARK: Internals

    private func savedURLs() -> [URL] {
        let files =
            (try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("save-") }
    }

    /// Shared tolerant decode: version-gated and geometry-checked. See `load`.
    private func decode(_ data: Data?) -> GameSnapshot? {
        guard let data,
            let snapshot = try? JSONDecoder().decode(GameSnapshot.self, from: data),
            snapshot.version <= GameSnapshot.currentVersion,
            snapshot.isConsistent
        else { return nil }
        return snapshot.migrated()
    }
}
