import XCTest

@testable import DonpaCore

final class GameConfigTests: XCTestCase {

    // MARK: Basic presets keep exact original numbers

    func testBasicPresetDimensions() {
        XCTAssertEqual(tuple(GameConfig.basic(.beginner)), [9, 9, 10])
        XCTAssertEqual(tuple(GameConfig.basic(.intermediate)), [16, 16, 40])
        XCTAssertEqual(tuple(GameConfig.basic(.expert)), [30, 16, 99])
    }

    // MARK: Grid/Hive = size × density (mine = round(density × cells))

    func testGridMineCounts() {
        // S = 16×16 = 256 cells. easy .10→26, normal .12→31, hard .14→36,
        // brutal .16→41, insane .18→46.
        XCTAssertEqual(GameConfig.grid(.s, .easy, .flat).mineCount, 26)
        XCTAssertEqual(GameConfig.grid(.s, .normal, .flat).mineCount, 31)
        XCTAssertEqual(GameConfig.grid(.s, .hard, .flat).mineCount, 36)
        XCTAssertEqual(GameConfig.grid(.s, .brutal, .flat).mineCount, 41)
        XCTAssertEqual(GameConfig.grid(.s, .insane, .flat).mineCount, 46)
        // Power-of-two ladder (XS=8, M=32, L=64, XL=128, XXL=256, XXXL=1024).
        XCTAssertEqual(tuple(GameConfig.grid(.xs, .easy, .flat)).prefix(2), [8, 8])
        XCTAssertEqual(tuple(GameConfig.grid(.m, .easy, .flat)).prefix(2), [32, 32])
        XCTAssertEqual(tuple(GameConfig.grid(.l, .easy, .flat)).prefix(2), [64, 64])
        XCTAssertEqual(
            tuple(GameConfig.grid(.xxl, .easy, .flat)).prefix(2), [256, 256])
        XCTAssertEqual(
            tuple(GameConfig.grid(.xxxl, .easy, .flat)).prefix(2), [1024, 1024])
    }

    func testEveryConfigLeavesASafeCell() {
        let all = BoardFamily.allCases.flatMap { family in
            BoardEdges.allCases.flatMap { GameConfig.configs(family: family, edges: $0) }
        }
        for config in all {
            XCTAssertLessThan(
                config.mineCount, config.width * config.height,
                "\(config.label) must leave at least one safe cell")
        }
    }

    // MARK: Storage keys — versioned, geometry-bearing, forward-compatible

    func testBasicStorageKeys() {
        XCTAssertEqual(GameConfig.basic(.beginner).storageKey, "v2|basic|beginner")
        XCTAssertEqual(GameConfig.basic(.expert).storageKey, "v2|basic|expert")
    }

    func testCustomStorageKeyEncodesFamilyEdgesAndGeometry() {
        // S·Hard = 16×16, 36 mines (14%), Grid + Flat. The key is geometry-based,
        // so renaming a size case leaves existing scores' keys intact.
        XCTAssertEqual(
            GameConfig.grid(.s, .hard, .flat).storageKey,
            "v2|grid|flat|16x16|m36")
    }

    func testEveryConfigHasAUniqueStorageKey() {
        let all = BoardFamily.allCases.flatMap { family in
            BoardEdges.allCases.flatMap { GameConfig.configs(family: family, edges: $0) }
        }
        // Basic is enumerated once per edges value (it ignores edges) — dedupe the
        // configs first; the KEYS must then be unique.
        let keys = Set(all).map(\.storageKey)
        XCTAssertEqual(Set(keys).count, keys.count, "storage keys must be unique per config")
    }

    /// The format-lock guarantee: keys carry geometry, so if a tier were ever
    /// redefined to a different size, it would produce a DIFFERENT key — old
    /// scores stay attached to their real board rather than being silently
    /// re-pointed. We assert the key is a function of geometry, not the tier
    /// token, by comparing two configs that share a token but differ in size.
    func testKeyIsGeometryBoundNotTierBound() {
        // Two modern configs with the same density token but different sizes
        // must have different keys (because geometry differs).
        let xs = GameConfig.grid(.xs, .normal, .flat).storageKey
        let m = GameConfig.grid(.m, .normal, .flat).storageKey
        XCTAssertNotEqual(xs, m)
        // And the key contains the concrete geometry, not the word "normal".
        XCTAssertTrue(xs.contains("8x8"))
        XCTAssertFalse(xs.contains("normal"))
    }

    // MARK: Labels

    func testLabels() {
        XCTAssertEqual(GameConfig.basic(.beginner).label, "Beginner")
        // Size label is the shirt-size letter; density is a sapper tier.
        XCTAssertEqual(GameConfig.grid(.s, .hard, .flat).label, "S · Veteran")
        XCTAssertEqual(GameConfig.hive(.s, .hard, .round).label, "S · Veteran")
    }

    func testFullLabels() {
        // Family always named; Flat is the unmarked default, Round called out.
        XCTAssertEqual(GameConfig.basic(.beginner).fullLabel, "Beginner")
        XCTAssertEqual(GameConfig.grid(.s, .hard, .flat).fullLabel, "Grid · S · Veteran")
        XCTAssertEqual(GameConfig.hive(.s, .hard, .round).fullLabel, "Hive · S · Veteran · Round")
    }

    /// Every config in the head-to-head universe must be distinguishable by its
    /// full label — the exact ambiguity `label` has ("M · Veteran" ×4).
    func testFullLabelsAreUnique() {
        let all = BoardFamily.allCases.flatMap { family in
            BoardEdges.allCases.flatMap { edges in
                GameConfig.configs(family: family, edges: edges)
            }
        }
        // Basic ignores edges, so the sweep yields its presets twice — dedupe by
        // key first (as head-to-head does), then labels must be one per config.
        let unique = Dictionary(all.map { ($0.storageKey, $0) }) { first, _ in first }
        let labels = unique.values.map(\.fullLabel)
        XCTAssertEqual(labels.count, Set(labels).count)
    }

    // MARK: Rank insignia + axis accessors

    func testDensityInsigniaAscends() {
        // Enlisted tiers are 1/2/3 chevron stripes; the top two are officer marks.
        XCTAssertEqual(chevrons(.easy), 1)
        XCTAssertEqual(chevrons(.normal), 2)
        XCTAssertEqual(chevrons(.hard), 3)
        if case .star = Density.brutal.insignia {} else { XCTFail("brutal should be .star") }
        if case .staredLaurel = Density.insane.insignia {
        } else {
            XCTFail("insane should be .staredLaurel")
        }
    }

    func testAxisAccessors() {
        let grid = GameConfig.grid(.m, .brutal, .flat)
        XCTAssertEqual(grid.size, .m)
        XCTAssertEqual(grid.density, .brutal)
        XCTAssertEqual(grid.family, .grid)
        XCTAssertFalse(grid.isHex)
        XCTAssertEqual(GameConfig.hive(.m, .brutal, .round).family, .hive)
        XCTAssertTrue(GameConfig.hive(.m, .brutal, .round).isHex)
        // Basic configs have no size/density axes.
        XCTAssertNil(GameConfig.basic(.expert).size)
        XCTAssertNil(GameConfig.basic(.expert).density)
        XCTAssertEqual(GameConfig.basic(.expert).family, .basic)
        // The family-parameterized builder mirrors the cases; Basic has no axes.
        XCTAssertEqual(
            GameConfig.custom(.hive, .m, .brutal, .round), .hive(.m, .brutal, .round))
        XCTAssertNil(GameConfig.custom(.basic, .m, .brutal, .round))
    }

    private func chevrons(_ d: Density) -> Int? {
        if case .chevrons(let n) = d.insignia { return n }
        return nil
    }

    // MARK: A config builds a playable, winnable game (integration sanity)

    func testGridConfigProducesAPlayableGame() {
        var game = Game(config: .grid(.xs, .easy, .flat))
        var rng = SeededRNG(seed: 3)
        game.reveal(Coord(4, 4), using: &rng)
        XCTAssertNotEqual(game.status, .lost, "first click must be safe")
        XCTAssertEqual(game.mineCount, GameConfig.grid(.xs, .easy, .flat).mineCount)
    }

    private func tuple(_ c: GameConfig) -> [Int] { [c.width, c.height, c.mineCount] }

    // MARK: Picker detail + tagline strings (every case is non-empty, detail
    // carries the expected numbers). Asserts contracts, not exact copy, so a
    // tagline reword doesn't break the test — but every code path is exercised.

    func testBasicDetailAndTagline() {
        for preset in BasicPreset.allCases {
            let d = preset.dimensions
            let detail = preset.detail
            XCTAssertTrue(detail.contains("\(d.width)"), "detail names width: \(detail)")
            XCTAssertTrue(detail.contains("\(d.height)"), "detail names height: \(detail)")
            XCTAssertTrue(detail.contains("\(d.mines)"), "detail names mines: \(detail)")
            XCTAssertFalse(preset.tagline.isEmpty, "tagline non-empty for \(preset)")
        }
    }

    func testSizeDetailAndTagline() {
        for size in BoardSize.allCases {
            // The detail interpolates numbers with locale digit-grouping (e.g.
            // "1,000×1,000"), so compare on digits only.
            let digits = size.detail.filter(\.isNumber)
            XCTAssertTrue(digits.contains("\(size.side)"), "detail names side: \(size.detail)")
            XCTAssertFalse(size.tagline.isEmpty, "tagline non-empty for \(size)")
        }
    }

    func testDensityDetailAndTagline() {
        for density in Density.allCases {
            let gridPct = Int((density.fraction(hex: false) * 100).rounded())
            let hivePct = Int((density.fraction(hex: true) * 100).rounded())
            XCTAssertTrue(
                density.detail(hex: false).contains("\(gridPct)"),
                "grid detail names percent: \(density.detail(hex: false))")
            XCTAssertTrue(
                density.detail(hex: true).contains("\(hivePct)"),
                "hive detail names its denser percent: \(density.detail(hex: true))")
            XCTAssertFalse(density.tagline.isEmpty, "tagline non-empty for \(density)")
        }
    }

    /// Taglines are distinct within each axis (no copy-paste duplicates).
    func testTaglinesAreDistinctWithinEachAxis() {
        XCTAssertEqual(
            Set(BasicPreset.allCases.map(\.tagline)).count, BasicPreset.allCases.count)
        XCTAssertEqual(Set(BoardSize.allCases.map(\.tagline)).count, BoardSize.allCases.count)
        XCTAssertEqual(Set(Density.allCases.map(\.tagline)).count, Density.allCases.count)
    }

    // MARK: Round (torus) edges axis

    /// Every edges case has a distinct, non-empty label (the New Game picker's
    /// Flat/Round segments) and an id matching its rawValue.
    func testEdgesLabelsAndIDs() {
        let labels = BoardEdges.allCases.map(\.label)
        XCTAssertTrue(labels.allSatisfy { !$0.isEmpty }, "each edges case has a label")
        XCTAssertEqual(Set(labels).count, BoardEdges.allCases.count, "labels are distinct")
        for e in BoardEdges.allCases { XCTAssertEqual(e.id, e.rawValue) }
    }

    /// The `edges` axis selects the topology: Flat → bounded, Round → torus.
    func testEdgesSelectsTopology() {
        let flat = GameConfig.grid(.s, .normal, .flat)
        let round = GameConfig.grid(.s, .normal, .round)
        XCTAssertTrue(flat.topology is BoundedSquareTopology)
        XCTAssertTrue(round.topology is WrappedSquareTopology)
        XCTAssertEqual(flat.edges, .flat)
        XCTAssertEqual(round.edges, .round)
        XCTAssertFalse(flat.edges.wraps)
        XCTAssertTrue(round.edges.wraps)
        // Basic is always Flat.
        XCTAssertEqual(GameConfig.basic(.beginner).edges, .flat)
    }

    /// Flat and Round key distinctly (so their scores never collide), each
    /// carrying its edges token.
    func testEdgesDistinguishStorageKey() {
        let flat = GameConfig.grid(.s, .normal, .flat).storageKey
        let round = GameConfig.grid(.s, .normal, .round).storageKey
        XCTAssertNotEqual(flat, round)
        XCTAssertTrue(round.contains("round"), round)
        XCTAssertTrue(flat.contains("flat"), flat)
    }

    /// The family selects the topology and layout: Hive → HexTopology/HexLayout.
    func testFamilySelectsTopologyAndLayout() {
        let grid = GameConfig.grid(.s, .normal, .flat)
        let hive = GameConfig.hive(.s, .normal, .flat)
        XCTAssertTrue(grid.topology is BoundedSquareTopology)
        XCTAssertTrue(hive.topology is HexTopology)
        XCTAssertTrue(grid.layout() is SquareLayout)
        XCTAssertTrue(hive.layout() is HexLayout)
        // Basic is always square cells.
        XCTAssertFalse(GameConfig.basic(.beginner).isHex)
        XCTAssertTrue(GameConfig.basic(.beginner).layout() is SquareLayout)
    }

    /// The full family × edges matrix maps to the four topologies, including the
    /// Round hive torus (valid because every Grid/Hive size is even-sided).
    func testFamilyEdgesMatrixSelectsTopology() {
        XCTAssertTrue(
            GameConfig.grid(.s, .normal, .round).topology is WrappedSquareTopology)
        XCTAssertTrue(
            GameConfig.hive(.s, .normal, .round).topology is WrappedHexTopology)
        XCTAssertTrue(
            GameConfig.hive(.s, .normal, .flat).topology is HexTopology)
        // Every Grid/Hive size is even-sided, so the Round hive torus is always valid.
        for size in BoardSize.allCases {
            XCTAssertEqual(
                GameConfig.hive(size, .normal, .round).height % 2, 0,
                "\(size) must be even-sided for a hex torus")
        }
    }

    /// Grid and Hive key distinctly (separate scoreboards): the hive key carries
    /// its family token AND a higher mine count — Hive runs +2 density points, so
    /// S·Normal is 12% (31 mines) Grid vs 14% (36) Hive.
    func testFamilyDistinguishesStorageKey() {
        let grid = GameConfig.grid(.s, .normal, .flat).storageKey
        let hive = GameConfig.hive(.s, .normal, .flat).storageKey
        XCTAssertNotEqual(grid, hive)
        XCTAssertEqual(grid, "v2|grid|flat|16x16|m31")
        XCTAssertEqual(hive, "v2|hive|flat|16x16|m36")
    }

    /// Every family has a distinct, non-empty label (the New Game picker's
    /// Basic/Grid/Hive segments) and an id matching its rawValue.
    func testFamilyLabelsAndIDs() {
        let labels = BoardFamily.allCases.map(\.label)
        XCTAssertTrue(labels.allSatisfy { !$0.isEmpty }, "each family has a label")
        XCTAssertEqual(Set(labels).count, BoardFamily.allCases.count, "labels are distinct")
        for f in BoardFamily.allCases { XCTAssertEqual(f.id, f.rawValue) }
    }

    /// Hive boards carry +2 density points over Grid at every tier (its gentler
    /// 6-neighbour cascades were near one-tap on small boards); same size, more mines.
    func testHiveIsDenserThanGrid() {
        for density in Density.allCases {
            let grid = GameConfig.grid(.m, density, .flat).mineCount
            let hive = GameConfig.hive(.m, density, .flat).mineCount
            // M = 32×32 = 1024 cells, so +2 points ≈ +20 mines (±1 from rounding).
            XCTAssertEqual(Double(hive - grid), 0.02 * 1024, accuracy: 1.5, "\(density): +2pt")
        }
    }

    /// Every config round-trips through Codable with all axes intact.
    func testCodableRoundTripPreservesAllAxes() throws {
        for cfg in [
            GameConfig.hive(.m, .hard, .flat),
            GameConfig.hive(.s, .insane, .round),
            GameConfig.grid(.m, .hard, .round),
            GameConfig.grid(.l, .easy, .flat),
            GameConfig.basic(.expert),
        ] {
            let data = try JSONEncoder().encode(cfg)
            XCTAssertEqual(try JSONDecoder().decode(GameConfig.self, from: data), cfg)
        }
    }

    /// A save written in the pre-family (classic/modern) wire format is REJECTED —
    /// by design: the loader then discards the in-progress save and starts fresh
    /// (records are the thing we never lose; a mid-game is a shrug).
    func testRejectsPreFamilyWireFormat() {
        for legacy in [
            #"{"classic":{"_0":"beginner"}}"#,
            #"{"modern":{"_0":"m","_1":"hard","_2":"wrapped","_3":"hex"}}"#,
        ] {
            XCTAssertThrowsError(
                try JSONDecoder().decode(GameConfig.self, from: Data(legacy.utf8)),
                "the old vocabulary must not silently decode into something else")
        }
    }
}
