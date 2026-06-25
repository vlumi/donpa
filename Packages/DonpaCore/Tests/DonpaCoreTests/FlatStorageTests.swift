import XCTest

@testable import DonpaCore

/// Big-board groundwork: `Board` stores cells in a flat row-major array, the
/// huge-board memory/speed path. These pin the new seam — index mapping, storage
/// behaviour, and that a 1M-cell board is actually usable (cell writes O(1), not
/// O(n) array copies).
final class FlatStorageTests: XCTestCase {
    // MARK: RectangularTopology index mapping

    func testIndexRoundTrip() {
        let topo = BoundedSquareTopology(width: 7, height: 5)
        for c in topo.allCoords() {
            let i = topo.index(of: c)
            XCTAssertNotNil(i)
            XCTAssertEqual(topo.coord(at: i!), c, "index→coord must invert coord→index")
        }
    }

    func testIndexIsRowMajorAndDense() {
        let topo = BoundedSquareTopology(width: 4, height: 3)
        XCTAssertEqual(topo.index(of: Coord(0, 0)), 0)
        XCTAssertEqual(topo.index(of: Coord(3, 0)), 3)
        XCTAssertEqual(topo.index(of: Coord(0, 1)), 4)
        XCTAssertEqual(topo.index(of: Coord(3, 2)), 11)  // cellCount - 1
        // Indices densely fill 0..<cellCount.
        let indices = Set(topo.allCoords().map { topo.index(of: $0)! })
        XCTAssertEqual(indices, Set(0..<topo.cellCount))
    }

    func testIndexRejectsOffBoard() {
        let topo = BoundedSquareTopology(width: 4, height: 4)
        XCTAssertNil(topo.index(of: Coord(-1, 0)))
        XCTAssertNil(topo.index(of: Coord(4, 0)))
        XCTAssertNil(topo.index(of: Coord(0, 4)))
    }

    func testWrappedTopologyIsRectangular() {
        // Wrapped grids are dense rectangles too → flat storage eligible.
        let topo = WrappedSquareTopology(width: 6, height: 6)
        XCTAssertTrue((topo as Topology) is RectangularTopology)
        XCTAssertEqual(topo.index(of: Coord(5, 5)), 35)
    }

    // MARK: Board behaviour parity (flat-backed)

    func testFlatBoardStoresAndReturnsCells() {
        var board = Board(topology: BoundedSquareTopology(width: 5, height: 5))
        XCTAssertEqual(board[Coord(2, 3)].state, .hidden)  // default
        board[Coord(2, 3)].state = .revealed
        board[Coord(4, 4)].state = .flagged
        XCTAssertEqual(board[Coord(2, 3)].state, .revealed)
        XCTAssertEqual(board[Coord(4, 4)].state, .flagged)
        // Untouched cells stay default.
        XCTAssertEqual(board[Coord(0, 0)].state, .hidden)
    }

    func testDerivedCoordSetsMatchWrites() {
        var board = Board(topology: BoundedSquareTopology(width: 6, height: 6))
        board.placeMines(at: [Coord(1, 1), Coord(2, 2)])
        board[Coord(0, 0)].state = .revealed
        board[Coord(5, 5)].state = .flagged
        XCTAssertEqual(board.mineCoords, [Coord(1, 1), Coord(2, 2)])
        XCTAssertEqual(board.revealedCoords, [Coord(0, 0)])
        XCTAssertEqual(board.flaggedCoords, [Coord(5, 5)])
        XCTAssertEqual(board.revealedSafeCount, 1)
    }

    func testAdjacencyComputedOnFlatBoard() {
        var board = Board(topology: BoundedSquareTopology(width: 3, height: 3))
        board.placeMines(at: [Coord(0, 0)])
        // Centre touches the single corner mine → 1; opposite corner → 0.
        XCTAssertEqual(board[Coord(1, 1)].adjacentMines, 1)
        XCTAssertEqual(board[Coord(2, 2)].adjacentMines, 0)
    }

    func testOffBoardWriteIsIgnored() {
        var board = Board(topology: BoundedSquareTopology(width: 4, height: 4))
        board[Coord(99, 99)].state = .revealed  // off-board: no-op, no crash
        XCTAssertEqual(board.revealedCoords, [])
    }

    // MARK: Huge board — the point of the whole change

    /// A 1000×1000 (1M-cell) board must build and take per-cell writes without
    /// O(n) array copies (which would make this hang). If flat storage isn't
    /// copy-on-write-in-place, this test wouldn't finish in reasonable time.
    func testMillionCellBoardIsUsable() {
        let n = 1000
        var board = Board(topology: BoundedSquareTopology(width: n, height: n))
        XCTAssertEqual(board.cellCount, n * n)
        // Many scattered single-cell writes — each must be O(1).
        for k in stride(from: 0, to: n * n, by: 1000) {
            board[Coord(k % n, k / n)].state = .flagged
        }
        XCTAssertEqual(board.flagCount, (n * n) / 1000)
    }

    /// `placeMines` writes EVERY cell twice (isMine pass + adjacency pass) — the
    /// heaviest board operation. It must stay O(n): if flat storage copies the
    /// array per write (e.g. an enum-cased array losing copy-on-write), this turns
    /// O(n²) and a 250k-cell board takes tens of seconds. Guards that regression.
    func testPlaceMinesScalesLinearly() {
        var board = Board(topology: BoundedSquareTopology(width: 500, height: 500))
        var mines: Set<Coord> = []
        for k in stride(from: 0, to: 250_000, by: 7) { mines.insert(Coord(k % 500, k / 500)) }
        let start = Date()
        board.placeMines(at: mines)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(board.mineCount, mines.count)
        // O(n) finishes in well under a second on CI hardware; O(n²) took ~27s.
        // Generous ceiling to avoid flakiness while still catching the blowup.
        XCTAssertLessThan(elapsed, 5.0, "placeMines on 250k cells must be O(n)")
    }
}
