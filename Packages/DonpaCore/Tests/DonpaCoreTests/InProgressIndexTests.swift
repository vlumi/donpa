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

    func testDensityDotFilteredByFamily() {
        // 'normal' has a save in Grid, not in Hive; 'dense' the reverse.
        XCTAssertTrue(index.densityHasSave(.normal, family: .grid))
        XCTAssertFalse(index.densityHasSave(.hard, family: .grid))
        XCTAssertTrue(index.densityHasSave(.hard, family: .hive))
        XCTAssertFalse(index.densityHasSave(.normal, family: .hive))
    }

    func testSizeDotFilteredByFamilyAndDensity() {
        // Grid+normal has a save at M only.
        XCTAssertTrue(index.sizeHasSave(.m, family: .grid, density: .normal))
        XCTAssertFalse(index.sizeHasSave(.s, family: .grid, density: .normal))
        // Grid+dense has none, so no size lights up under that path.
        XCTAssertFalse(index.sizeHasSave(.m, family: .grid, density: .hard))
    }

    func testEdgesDotFilteredByFullPathAbove() {
        // Grid+normal+M has a save at flat only.
        XCTAssertTrue(index.edgesHasSave(.flat, family: .grid, density: .normal, size: .m))
        XCTAssertFalse(index.edgesHasSave(.round, family: .grid, density: .normal, size: .m))
        // Hive+dense+S is round.
        XCTAssertTrue(index.edgesHasSave(.round, family: .hive, density: .hard, size: .s))
    }

    func testEmptyIndexLightsNothing() {
        let empty = InProgressIndex(savedConfigs: [])
        XCTAssertFalse(empty.familyHasSave(.grid))
        XCTAssertFalse(empty.hasSave(for: .grid(.m, .normal, .flat)))
    }
}
