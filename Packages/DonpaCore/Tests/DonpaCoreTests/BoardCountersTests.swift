import XCTest

@testable import DonpaCore

/// `Board.mineCount`/`flagCount` are maintained incrementally (set in
/// `placeMines`, adjusted in the cell subscript) rather than scanned, so this
/// pins the invariants: they must always match a full scan.
final class BoardCountersTests: XCTestCase {
    private func scannedFlags(_ board: Board) -> Int {
        board.allCoords.filter { board[$0].state == .flagged }.count
    }

    func testEmptyBoardHasZeroCounts() {
        let board = Board(topology: BoundedSquareTopology(width: 5, height: 5))
        XCTAssertEqual(board.mineCount, 0)
        XCTAssertEqual(board.flagCount, 0)
    }

    func testMineCountAfterPlacement() {
        var board = Board(topology: BoundedSquareTopology(width: 5, height: 5))
        board.placeMines(at: [Coord(0, 0), Coord(1, 1), Coord(2, 2)])
        XCTAssertEqual(board.mineCount, 3)
    }

    func testFlagCountTracksFlagAndUnflag() {
        var board = Board(topology: BoundedSquareTopology(width: 4, height: 4))
        XCTAssertEqual(board.flagCount, 0)

        board[Coord(0, 0)].state = .flagged
        board[Coord(1, 0)].state = .flagged
        XCTAssertEqual(board.flagCount, 2)
        XCTAssertEqual(board.flagCount, scannedFlags(board))

        // Unflag one.
        board[Coord(0, 0)].state = .hidden
        XCTAssertEqual(board.flagCount, 1)
        XCTAssertEqual(board.flagCount, scannedFlags(board))
    }

    func testReflaggingSameCellDoesNotDoubleCount() {
        var board = Board(topology: BoundedSquareTopology(width: 4, height: 4))
        board[Coord(2, 2)].state = .flagged
        // Writing the same state again must not increment again.
        board[Coord(2, 2)].state = .flagged
        XCTAssertEqual(board.flagCount, 1)
    }

    func testFlaggedToRevealedDecrements() {
        var board = Board(topology: BoundedSquareTopology(width: 4, height: 4))
        board[Coord(0, 0)].state = .flagged
        XCTAssertEqual(board.flagCount, 1)
        // A direct flag→revealed transition (e.g. chord) still decrements.
        board[Coord(0, 0)].state = .revealed
        XCTAssertEqual(board.flagCount, 0)
        XCTAssertEqual(board.flagCount, scannedFlags(board))
    }

    // MARK: Over-flag detection (passive error cue)

    /// A 3×3 with one corner mine makes the centre a "1". Revealed and given more
    /// than one flag around it, it's over-flagged — a guaranteed mistake.
    func testOverFlaggedFiresOnlyWhenFlagsExceedCount() {
        var board = Board(topology: BoundedSquareTopology(width: 3, height: 3))
        board.placeMines(at: [Coord(0, 0)])  // centre (1,1) → adjacentMines == 1
        board[Coord(1, 1)].state = .revealed

        XCTAssertFalse(board.isOverFlagged(Coord(1, 1)), "no flags → not over-flagged")
        board[Coord(0, 1)].state = .flagged
        XCTAssertFalse(board.isOverFlagged(Coord(1, 1)), "flags == count → satisfied, not over")
        board[Coord(1, 0)].state = .flagged
        XCTAssertTrue(board.isOverFlagged(Coord(1, 1)), "2 flags around a 1 → over-flagged")
    }

    /// Only revealed numbered cells qualify: hidden / flagged / a 0 never do, even
    /// with flags nearby.
    func testOverFlaggedIgnoresNonNumberedCells() {
        var board = Board(topology: BoundedSquareTopology(width: 3, height: 3))
        board.placeMines(at: [Coord(0, 0)])
        board[Coord(0, 1)].state = .flagged
        board[Coord(1, 0)].state = .flagged
        // (2,2) is a revealed 0 — no count to exceed.
        board[Coord(2, 2)].state = .revealed
        XCTAssertFalse(board.isOverFlagged(Coord(2, 2)), "a revealed 0 is never over-flagged")
        // The centre while still hidden doesn't qualify.
        XCTAssertFalse(board.isOverFlagged(Coord(1, 1)), "a hidden cell is never over-flagged")
    }
}
