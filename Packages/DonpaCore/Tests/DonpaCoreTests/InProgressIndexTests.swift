import XCTest

@testable import DonpaCore

/// The top-down drill-down: each selector level's dot is filtered by the choices above
/// it, so following lit chips down always reaches a real save.
final class InProgressIndexTests: XCTestCase {
    // A Grid save at M / normal / flat, and a Hive save at S / dense / round.
    private let index = InProgressIndex(savedConfigs: [
        .grid(.m, .normal, .flat),
        .hive(.s, .hard, .round),
        .basic(.expert),
    ])

    func testExactMatchDrivesContinue() {
        XCTAssertTrue(index.hasSave(for: .grid(.m, .normal, .flat)))
        XCTAssertFalse(index.hasSave(for: .grid(.m, .normal, .round)))  // different edge
        XCTAssertTrue(index.hasSave(for: .basic(.expert)))
        XCTAssertFalse(index.hasSave(for: .basic(.beginner)))
    }

    func testFamilyDots() {
        XCTAssertTrue(index.familyHasSave(.grid))
        XCTAssertTrue(index.familyHasSave(.hive))
        XCTAssertTrue(index.familyHasSave(.basic))
    }

    func testSizeDotFilteredByFamily() {
        // Grid has a save at M; Hive at S. Hierarchy: family → SIZE first.
        XCTAssertTrue(index.sizeHasSave(.m, family: .grid))
        XCTAssertFalse(index.sizeHasSave(.s, family: .grid))
        XCTAssertTrue(index.sizeHasSave(.s, family: .hive))
        XCTAssertFalse(index.sizeHasSave(.m, family: .hive))
    }

    func testDensityDotFilteredByFamilyAndSize() {
        // Grid+M has a save at 'normal' only.
        XCTAssertTrue(index.densityHasSave(.normal, family: .grid, size: .m))
        XCTAssertFalse(index.densityHasSave(.hard, family: .grid, size: .m))
        // Grid+S has none, so no density lights up under that path.
        XCTAssertFalse(index.densityHasSave(.normal, family: .grid, size: .s))
    }

    func testEdgesDotFilteredByFullPathAbove() {
        // Grid+M+normal has a save at flat only.
        XCTAssertTrue(index.edgesHasSave(.flat, family: .grid, size: .m, density: .normal))
        XCTAssertFalse(index.edgesHasSave(.round, family: .grid, size: .m, density: .normal))
        // Hive+S+hard is round.
        XCTAssertTrue(index.edgesHasSave(.round, family: .hive, size: .s, density: .hard))
    }

    func testPresetDots() {
        // Basic has no size/density/edges to drill — the preset chip lights directly.
        XCTAssertTrue(index.presetHasSave(.expert))
        XCTAssertFalse(index.presetHasSave(.beginner))
    }

    func testEmptyIndexLightsNothing() {
        let empty = InProgressIndex(savedConfigs: [])
        XCTAssertFalse(empty.familyHasSave(.grid))
        XCTAssertFalse(empty.presetHasSave(.expert))
        XCTAssertFalse(empty.hasSave(for: .grid(.m, .normal, .flat)))
    }
}
