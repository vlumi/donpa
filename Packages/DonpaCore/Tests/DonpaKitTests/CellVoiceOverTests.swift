import DonpaCore
import XCTest

@testable import DonpaKit

/// The focused cell's spoken description: coordinates flip to top-down rows
/// (row 1 = top; the board renders rows bottom-up) and every cell state has a
/// wording, including the "?" mark. English values — the test bundle's default.
final class CellVoiceOverTests: XCTestCase {
    private func cell(
        _ state: CellState, mine: Bool = false, adjacent: Int = 0
    ) -> Cell {
        var c = Cell()
        c.state = state
        c.isMine = mine
        c.adjacentMines = adjacent
        return c
    }

    func testRowsSpeakTopDownAndColumnsLeftToRight() {
        // On a 9-row board, index y=8 is the visual TOP row → spoken row 1;
        // x=0 is the leftmost column → spoken column 1.
        let top = CellVoiceOver.describe(cell(.hidden), at: Coord(0, 8), boardHeight: 9)
        XCTAssertTrue(top.hasPrefix("Row 1, column 1"), top)
        let bottom = CellVoiceOver.describe(cell(.hidden), at: Coord(4, 0), boardHeight: 9)
        XCTAssertTrue(bottom.hasPrefix("Row 9, column 5"), bottom)
    }

    func testEveryStateHasAWording() {
        let h = 5
        let at = Coord(2, 2)
        XCTAssertTrue(
            CellVoiceOver.describe(cell(.hidden), at: at, boardHeight: h)
                .hasSuffix("hidden"))
        XCTAssertTrue(
            CellVoiceOver.describe(cell(.flagged), at: at, boardHeight: h)
                .hasSuffix("flagged"))
        XCTAssertTrue(
            CellVoiceOver.describe(cell(.questioned), at: at, boardHeight: h)
                .hasSuffix("question mark"))
        XCTAssertTrue(
            CellVoiceOver.describe(cell(.revealed, mine: true), at: at, boardHeight: h)
                .hasSuffix("mine"))
        XCTAssertTrue(
            CellVoiceOver.describe(cell(.revealed), at: at, boardHeight: h)
                .hasSuffix("open, clear"))
        XCTAssertTrue(
            CellVoiceOver.describe(cell(.revealed, adjacent: 3), at: at, boardHeight: h)
                .hasSuffix("open, 3"))
    }
}
