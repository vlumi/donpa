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

    func testLatestIsNilWhenNoSaves() {
        XCTAssertNil(store.latest())
        XCTAssertTrue(store.all().isEmpty)
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
        try Data(
            #"{"config":{"basic":{"preset":"beginner"}},"mines":[[0,0],[1,1],[2,2]]}"#.utf8
        ).write(to: fileURL(for: .basic(.beginner)))
        XCTAssertTrue(store.hasSave(config: .basic(.beginner)), "the file exists…")
        XCTAssertNil(
            store.load(config: .basic(.beginner)), "…but an inconsistent save must not load")
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
        try Data(json.utf8).write(to: fileURL(for: .basic(.beginner)))
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
        try Data(json.utf8).write(to: fileURL(for: .basic(.beginner)))
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
