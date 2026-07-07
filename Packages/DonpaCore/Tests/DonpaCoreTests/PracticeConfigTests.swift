import XCTest

@testable import DonpaCore

/// The Range as a `GameConfig` family: its axes, keys, and the no-guess
/// placement wiring in `Game`. Generator internals live in `PracticeBoardTests`.
final class PracticeConfigTests: XCTestCase {

    // MARK: Config surface

    func testAxes() {
        let config = GameConfig.practice(.m)
        XCTAssertEqual(config.family, .practice)
        XCTAssertEqual(config.size, .m)
        XCTAssertNil(config.density, "The Range has no density axis")
        XCTAssertEqual(config.edges, .flat)
        XCTAssertFalse(config.isHex)
    }

    func testMineCountsAreTwelvePercent() {
        // side² × 0.12, rounded — the Sapper (Normal) count on each size.
        XCTAssertEqual(GameConfig.practice(.xs).mineCount, 8)  // 64 cells
        XCTAssertEqual(GameConfig.practice(.s).mineCount, 31)  // 256
        XCTAssertEqual(GameConfig.practice(.m).mineCount, 123)  // 1 024
        XCTAssertEqual(GameConfig.practice(.l).mineCount, 492)  // 4 096
        XCTAssertEqual(GameConfig.practice(.xl).mineCount, 1966)  // 16 384
    }

    func testMatchesGridNormalMineCount() {
        // Same count as Grid Sapper on the same size: familiar boards, minus luck.
        XCTAssertEqual(
            GameConfig.practice(.s).mineCount,
            GameConfig.grid(.s, .normal, .flat).mineCount)
    }

    func testStorageKey() {
        // Geometry-bearing like the other families', minus the edges axis —
        // and distinct from the same-geometry Grid key.
        XCTAssertEqual(GameConfig.practice(.s).storageKey, "v2|practice|16x16|m31")
        XCTAssertNotEqual(
            GameConfig.practice(.s).storageKey,
            GameConfig.grid(.s, .normal, .flat).storageKey)
    }

    func testLabels() {
        XCTAssertEqual(GameConfig.practice(.m).label, "M")
        XCTAssertEqual(GameConfig.practice(.m).fullLabel, "The Range · M")
    }

    func testConfigsEnumeratesTheSizeLadder() {
        let configs = GameConfig.configs(family: .practice)
        XCTAssertEqual(configs, GameConfig.practiceSizes.map(GameConfig.practice))
        XCTAssertEqual(
            GameConfig.practiceSizes, [.xs, .s, .m, .l, .xl],
            "XS–XL by design — the huge boards stay out of the mode")
        XCTAssertEqual(Set(configs.map(\.storageKey)).count, configs.count)
    }

    func testCustomDoesNotBuildPracticeConfigs() {
        // `custom` is the density×edges factory; The Range has neither axis.
        XCTAssertNil(GameConfig.custom(.practice, .m, .normal, .flat))
    }

    func testCodableRoundTrip() throws {
        for config in GameConfig.configs(family: .practice) {
            let data = try JSONEncoder().encode(config)
            XCTAssertEqual(try JSONDecoder().decode(GameConfig.self, from: data), config)
        }
    }

    func testFamilyIsGatedOutOfAllCases() {
        // The UI PR flips this: until The Range's page ships, every
        // family-enumerating surface (pickers, filters, breakdowns) skips it.
        XCTAssertFalse(BoardFamily.allCases.contains(.practice))
        XCTAssertEqual(BoardFamily.allCases, [.basic, .grid, .hive])
        XCTAssertEqual(BoardFamily.practice.label, "The Range")
    }

    // MARK: Game wiring

    func testConfigSelectsPlacement() {
        XCTAssertEqual(Game(config: .practice(.xs)).placement, .noGuess)
        XCTAssertEqual(Game(config: .grid(.xs, .normal, .flat)).placement, .standard)
    }

    func testEagerArmIsANoOpForNoGuess() {
        // The layout depends on the first click, so there is nothing to pre-arm;
        // the board must still be empty when the click arrives.
        var game = Game(config: .practice(.xs))
        var rng = SeededGenerator(seed: 7)
        game.placeMinesEagerly(using: &rng)
        XCTAssertTrue(game.board.mineCoords.isEmpty)
        XCTAssertEqual(game.status, .notStarted)
    }

    func testFirstRevealGeneratesASolvableBoard() {
        let config = GameConfig.practice(.xs)
        let click = Coord(4, 4)
        for seed in UInt64(1)...4 {
            var rng = SeededGenerator(seed: seed)
            var game = Game(config: config)
            game.reveal(click, using: &rng)
            XCTAssertEqual(game.status, .playing)
            XCTAssertEqual(game.board.mineCoords.count, config.mineCount)

            // Replay the layout from the same click: pure deduction must win.
            var replay = Game(topology: config.topology, mines: game.board.mineCoords)
            var solverRng = SeededGenerator(seed: seed &+ 1000)
            let result = Solver().solve(&replay, firstClick: click, using: &solverRng)
            XCTAssertTrue(
                result.solvedWithoutGuessing,
                "seed \(seed): the wired-up first reveal must produce a no-guess board")
        }
    }

    func testNoGuessFallbackStillPlacesAFullLayout() {
        // The generator's give-up path: an off-board click makes it bail
        // immediately (unreachable through `reveal`, which normalizes first),
        // and the fallback must still deliver a standard first-click-safe layout.
        let topology = BoundedSquareTopology(width: 8, height: 8)
        var rng = SeededGenerator(seed: 3)
        let mines = Game.noGuessMines(
            topology: topology, mineCount: 8, firstClick: Coord(-1, -1), using: &rng)
        XCTAssertEqual(mines.count, 8)
    }
}
