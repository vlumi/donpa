import XCTest

@testable import DonpaCore

final class SaveStoreTests: XCTestCase {
    private var store: SaveStore!
    private var dir: URL!

    override func setUp() {
        super.setUp()
        // A unique temp dir per test, so tests don't collide or touch the real
        // App Support saves. The store keeps its files in a `saves/` subdir of this.
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("donpa-savetest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = SaveStore(directory: dir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    /// The `saves/save-<sanitized key>.json` path the store uses, for fixture writes.
    private func fileURL(for config: GameConfig) -> URL {
        let safe = String(config.storageKey.map { $0.isLetter || $0.isNumber ? $0 : "_" })
        return dir.appendingPathComponent("saves/save-\(safe).json")
    }

    /// Write a save fixture the way the store would: magic + zlib(json). Fixtures
    /// must pass the container gate so the tests exercise the SEMANTIC gates
    /// (version / geometry / status), not the magic check.
    private func writeFixture(_ json: String, for config: GameConfig) throws {
        let compressed = try (Data(json.utf8) as NSData).compressed(using: .zlib) as Data
        try (Data("DONPAZ1\n".utf8) + compressed).write(to: fileURL(for: config))
    }

    private func sampleSnapshot(
        _ config: GameConfig = .basic(.beginner), elapsed: Int = 500, at: Date = Date()
    ) -> GameSnapshot {
        var game = Game(config: config)
        game.reveal(Coord(0, 0))
        return GameSnapshot(
            game: game, config: config, elapsedCentiseconds: elapsed, updatedAt: at)!
    }

    func testSaveThenLoadRoundTrips() {
        let config = GameConfig.basic(.beginner)
        XCTAssertNil(store.load(config: config))
        let snap = sampleSnapshot(config)
        store.save(snap)
        XCTAssertTrue(store.hasSave(config: config))
        let loaded = store.load(config: config)
        XCTAssertEqual(loaded?.elapsedCentiseconds, 500)
        XCTAssertEqual(loaded?.mines, snap.mines)
    }

    func testSavesAreKeptPerConfig() {
        let beginner = GameConfig.basic(.beginner)
        let expert = GameConfig.basic(.expert)
        store.save(sampleSnapshot(beginner, elapsed: 100))
        store.save(sampleSnapshot(expert, elapsed: 900))
        // Each config keeps its own game — saving one doesn't clobber the other.
        XCTAssertEqual(store.load(config: beginner)?.elapsedCentiseconds, 100)
        XCTAssertEqual(store.load(config: expert)?.elapsedCentiseconds, 900)
        // Clearing one leaves the other.
        store.clear(config: beginner)
        XCTAssertFalse(store.hasSave(config: beginner))
        XCTAssertTrue(store.hasSave(config: expert))
    }

    func testAllAndLatestSortByUpdatedAt() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        store.save(sampleSnapshot(.basic(.beginner), at: t0))
        store.save(sampleSnapshot(.basic(.expert), at: t0.addingTimeInterval(300)))
        store.save(sampleSnapshot(.basic(.intermediate), at: t0.addingTimeInterval(60)))
        // Newest-played first: expert (+300), intermediate (+60), beginner (0).
        XCTAssertEqual(
            store.all().map(\.config), [.basic(.expert), .basic(.intermediate), .basic(.beginner)])
        XCTAssertEqual(store.latest()?.config, .basic(.expert))
    }

    /// Summaries mirror all(): same gating, same order, plus the derived progress —
    /// without retaining board sets (they feed Home's list across view updates).
    func testSummariesMirrorAllWithProgress() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        store.save(sampleSnapshot(.basic(.beginner), elapsed: 700, at: t0))
        store.save(sampleSnapshot(.basic(.expert), at: t0.addingTimeInterval(60)))
        let summaries = store.summaries()
        XCTAssertEqual(summaries.map(\.config), [.basic(.expert), .basic(.beginner)])
        XCTAssertEqual(summaries.last?.elapsedCentiseconds, 700)
        // Beginner: 9×9 − 10 mines = 71 safe cells; the sample revealed at least one,
        // so progress is a small positive percent (never 0 rounded up dishonestly).
        let progress = summaries.last?.progressPercent ?? -1
        XCTAssertTrue((0...99).contains(progress), "in-progress game is under 100%")
        XCTAssertEqual(
            summaries.last?.revealedSafeCount,
            store.load(config: .basic(.beginner))?.revealedSafeCount)
    }

    func testLatestIsNilWhenNoSaves() {
        XCTAssertNil(store.latest())
        XCTAssertTrue(store.all().isEmpty)
    }

    /// A save writes its tiny sidecar summary; clearing removes both. The sidecars
    /// are what make listing dozens of saves cheap (a full XXXL save is ~2MB JSON).
    func testSaveWritesSidecarAndClearRemovesIt() {
        let config = GameConfig.basic(.beginner)
        let sidecar = dir.appendingPathComponent("saves/summary-v2_basic_beginner.json")
        store.save(sampleSnapshot(config))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecar.path), "sidecar written")
        store.clear(config: config)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: sidecar.path), "sidecar cleared with the save")
    }

    /// Saves are zlib-compressed on disk (magic-prefixed), and smaller than their
    /// plain encoding — coordinate-list JSON compresses hard, and a save GROWS as
    /// the board gets played. Corrupt compressed data must not load.
    func testSavesAreCompressedOnDisk() throws {
        let config = GameConfig.basic(.expert)  // 30×16 · 99 mines → a real payload
        let snap = sampleSnapshot(config)
        store.save(snap)
        let file = try Data(contentsOf: fileURL(for: config))
        XCTAssertTrue(file.starts(with: Data("DONPAZ1\n".utf8)), "magic-prefixed zlib")
        let plain = try JSONEncoder().encode(snap)
        XCTAssertLessThan(file.count, plain.count, "compressed beats plain")
        // Round-trips through the compressed form.
        XCTAssertEqual(store.load(config: config)?.mines, snap.mines)
        // Magic + garbage is rejected like any unreadable file, not crashed on.
        try (Data("DONPAZ1\n".utf8) + Data("not deflate".utf8))
            .write(to: fileURL(for: .basic(.beginner)))
        XCTAssertNil(store.load(config: .basic(.beginner)))
    }

    /// A main file that isn't our container AT ALL (a pre-compression relic, or
    /// corruption) is DROPPED at listing time — main and sidecar both — even when a
    /// stale sidecar vouches for it. A lying sidecar made unreadable saves list as
    /// phantom rows whose resume silently did nothing.
    func testSummariesDropDeadRelicsDespiteSidecar() throws {
        let config = GameConfig.basic(.beginner)
        // Plant a stale sidecar (as a previous build's heal pass would have), then
        // overwrite the main file with plain JSON (the pre-compression format).
        store.save(sampleSnapshot(config))
        try Data(#"{"config":{"basic":{"preset":"beginner"}},"mines":[]}"#.utf8)
            .write(to: fileURL(for: config))
        XCTAssertTrue(store.summaries().isEmpty, "the phantom row is gone")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fileURL(for: config).path),
            "the dead main file was dropped")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("saves/summary-v2_basic_beginner.json").path),
            "its sidecar too")
    }

    /// A FUTURE container version (a downgraded app seeing a newer build's save) is
    /// hidden but NOT deleted — that's the future build's data, not a relic.
    func testSummariesPreserveFutureContainerVersions() throws {
        let config = GameConfig.basic(.beginner)
        try (Data("DONPAZ9\n".utf8) + Data("whatever future bytes".utf8))
            .write(to: fileURL(for: config))
        XCTAssertTrue(store.summaries().isEmpty, "hidden from the list")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fileURL(for: config).path),
            "but preserved on disk for the build that wrote it")
    }

    /// A save whose sidecar has gone missing still lists — via a one-time full
    /// decode that HEALS by writing the sidecar for next time.
    func testSummariesHealMissingSidecar() throws {
        store.save(sampleSnapshot(.basic(.beginner), elapsed: 420))
        let sidecar = dir.appendingPathComponent("saves/summary-v2_basic_beginner.json")
        try FileManager.default.removeItem(at: sidecar)
        let summaries = store.summaries()
        XCTAssertEqual(summaries.count, 1, "listed via the slow path")
        XCTAssertEqual(summaries.first?.elapsedCentiseconds, 420)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sidecar.path),
            "healed: the sidecar now exists for the fast path")
    }

    func testCameraViewSurvivesTheDiskRoundTrip() {
        let config = GameConfig.basic(.beginner)
        var game = Game(config: config)
        game.reveal(Coord(0, 0))
        let camera = CameraView(centerX: 0.65, centerY: 0.25, scale: 2.2)
        let snap = GameSnapshot(
            game: game, config: config, elapsedCentiseconds: 500, camera: camera)!
        store.save(snap)
        XCTAssertEqual(
            store.load(config: config)?.camera, camera, "the camera view persists to disk")
    }

    /// A save whose geometry no longer matches its config (a between-builds retune) is
    /// discarded — restoring it would mangle the board.
    func testLoadRejectsInconsistentSave() throws {
        let stale = try JSONDecoder().decode(
            GameSnapshot.self,
            from: Data(
                #"{"config":{"basic":{"preset":"beginner"}},"mines":[[0,0],[1,1],[2,2]]}"#.utf8))
        XCTAssertFalse(stale.isConsistent)
        try writeFixture(
            #"{"config":{"basic":{"preset":"beginner"}},"mines":[[0,0],[1,1],[2,2]]}"#,
            for: .basic(.beginner))
        XCTAssertTrue(store.hasSave(config: .basic(.beginner)), "the file exists…")
        XCTAssertNil(
            store.load(config: .basic(.beginner)), "…but an inconsistent save must not load")
    }

    /// A finished (won/lost) game is not resumable. The capture init already refuses
    /// to snapshot a non-playing game, but a finished snapshot could still reach disk
    /// via a hand-written/legacy file — load/all must reject it so it never resurfaces
    /// as a stale "Continue". Geometry-consistent (Beginner = 9×9, 10 mines) so only
    /// the status gate can reject it.
    func testLoadRejectsFinishedGame() throws {
        let mines = ((0..<9).map { "[\($0),0]" } + ["[0,1]"]).joined(separator: ",")
        let json =
            #"{"config":{"basic":{"preset":"beginner"}},"mines":[\#(mines)],"status":"lost"}"#
        try writeFixture(json, for: .basic(.beginner))
        XCTAssertTrue(store.hasSave(config: .basic(.beginner)), "the file exists…")
        XCTAssertNil(
            store.load(config: .basic(.beginner)), "…but a finished game must not load")
        XCTAssertTrue(store.all().isEmpty, "and it doesn't appear in the in-progress list")
    }

    func testClearRemovesTheSave() {
        let config = GameConfig.basic(.beginner)
        store.save(sampleSnapshot(config))
        store.clear(config: config)
        XCTAssertFalse(store.hasSave(config: config))
        XCTAssertNil(store.load(config: config))
    }

    func testLoadToleratesGarbage() throws {
        try Data("not json at all".utf8).write(to: fileURL(for: .basic(.beginner)))
        XCTAssertNil(store.load(config: .basic(.beginner)))
    }

    func testLoadRejectsNewerVersion() throws {
        let json =
            #"{"version":999,"config":{"basic":{"preset":"beginner"}},"mines":[],"#
            + #""revealed":[],"flagged":[],"status":"playing","revealedSafeCount":0,"#
            + #""elapsedCentiseconds":0}"#
        try writeFixture(json, for: .basic(.beginner))
        XCTAssertNil(
            store.load(config: .basic(.beginner)),
            "a version this build doesn't understand is discarded")
    }

    func testLoadAcceptsOlderVersion() throws {
        // Additive format: a save at/below currentVersion still loads. Geometry-
        // consistent (Beginner = 9×9, 10 mines) to pass the load gate.
        let mines = ((0..<9).map { "[\($0),0]" } + ["[0,1]"]).joined(separator: ",")
        let json =
            #"{"version":0,"config":{"basic":{"preset":"beginner"}},"mines":[\#(mines)]}"#
        try writeFixture(json, for: .basic(.beginner))
        let loaded = store.load(config: .basic(.beginner))
        XCTAssertNotNil(loaded, "an older, compatible save is preserved across upgrade")
        XCTAssertEqual(loaded?.config, .basic(.beginner))
    }

    /// The old single-slot `currentGame.json` is discarded on init (no migration).
    func testDiscardsLegacySingleSave() throws {
        let legacy = dir.appendingPathComponent("currentGame.json")
        try Data(#"{"config":{"basic":{"preset":"beginner"}},"mines":[]}"#.utf8).write(to: legacy)
        _ = SaveStore(directory: dir)  // init discards it
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }

    // MARK: UI-test isolation

    func testEphemeralStoreStartsEmpty() {
        XCTAssertNil(SaveStore.ephemeral().latest(), "a fresh ephemeral store has no saved game")
    }

    func testUITestCleanLaunchFlagFalseInUnitTests() {
        XCTAssertFalse(SaveStore.isUITestCleanLaunch)
    }

    /// Exercise the production factory (resolves the real App Support dir) with a
    /// READ-ONLY call — `latest()` just lists, never writes, so it can't disturb a real
    /// save. Covers the `appSupport()` / `appSupportDirectory` path.
    func testAppSupportFactoryResolves() {
        // Doesn't assert a value (the machine may or may not have saves); the point is
        // the factory + dir resolution run without crashing.
        _ = SaveStore.appSupport().latest()
    }
}
