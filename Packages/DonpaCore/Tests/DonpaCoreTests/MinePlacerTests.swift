import XCTest

@testable import DonpaCore

final class MinePlacerTests: XCTestCase {

    func testPlacesExactCount() {
        let t = BoundedSquareTopology(width: 9, height: 9)
        var rng = SeededRNG(seed: 1)
        let mines = MinePlacer.placeMines(
            topology: t, mineCount: 10, firstClick: Coord(4, 4), using: &rng)
        XCTAssertEqual(mines.count, 10)
    }

    func testFirstClickAndNeighboursAreSafe() {
        let t = BoundedSquareTopology(width: 9, height: 9)
        let firstClick = Coord(4, 4)
        // Try many seeds: the safe zone must never contain a mine.
        for seed in UInt64(0)..<200 {
            var rng = SeededRNG(seed: seed)
            let mines = MinePlacer.placeMines(
                topology: t, mineCount: 10, firstClick: firstClick, using: &rng)
            var safeZone: Set<Coord> = [firstClick]
            safeZone.formUnion(t.neighbors(of: firstClick))
            XCTAssertTrue(
                mines.isDisjoint(with: safeZone),
                "seed \(seed) put a mine in the safe zone")
        }
    }

    func testDenseBoardStillExcludesFirstClick() {
        // Board so full of mines that the safe zone can't be fully honoured;
        // the clicked cell itself must still be mine-free.
        let t = BoundedSquareTopology(width: 3, height: 3)  // 9 cells
        let firstClick = Coord(1, 1)
        var rng = SeededRNG(seed: 7)
        let mines = MinePlacer.placeMines(
            topology: t, mineCount: 8, firstClick: firstClick, using: &rng)
        XCTAssertEqual(mines.count, 8)
        XCTAssertFalse(mines.contains(firstClick))
    }

    /// Placement on a 1M-cell board must scale with the mine count, not the cell
    /// count — it rejection-samples indices rather than materializing + filtering
    /// all 1,000,000 coords (the old `allCoords().filter`, slow through AnySequence).
    func testHugeBoardPlacementIsFast() {
        let t = BoundedSquareTopology(width: 1000, height: 1000)
        var rng = SeededRNG(seed: 11)
        let start = Date()
        let mines = MinePlacer.placeMines(
            topology: t, mineCount: 130_000, firstClick: Coord(500, 500), using: &rng)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(mines.count, 130_000)
        // Generous ceiling for CI; the point is it's not an O(cells) blowup.
        XCTAssertLessThan(elapsed, 2.0, "1M-board placement must scale with mines, not cells")
    }
}
