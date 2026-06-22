import XCTest

@testable import DonpaCore

/// Covers `Game`'s incremental safe-cell counter and `progress`, which back the
/// progress-% score and (via the same counter) O(1) win detection.
final class ProgressTests: XCTestCase {

    /// `revealedSafeCount` always equals the actual number of revealed non-mine
    /// cells on the board, and `progress` is that over the safe-cell total.
    func testCounterMatchesRevealedSafeCells() {
        var game = Game(difficulty: .beginner)
        var rng = SeededRNG(seed: 7)
        game.reveal(Coord(4, 4), using: &rng)

        let actual = game.board.allCoords.filter {
            game.board[$0].state == .revealed && !game.board[$0].isMine
        }.count
        XCTAssertEqual(game.revealedSafeCount, actual)
        XCTAssertEqual(
            game.progress, Double(actual) / Double(game.safeCellCount), accuracy: 1e-9)
    }

    func testSafeCellCountExcludesMines() {
        let game = Game(difficulty: .beginner)  // 9×9, 10 mines
        XCTAssertEqual(game.safeCellCount, 81 - 10)
    }

    func testProgressStartsAtZero() {
        let game = Game(difficulty: .beginner)
        XCTAssertEqual(game.revealedSafeCount, 0)
        XCTAssertEqual(game.progress, 0, accuracy: 1e-9)
    }

    /// A win means every safe cell is revealed → progress is exactly 1.0.
    func testWinIsFullProgress() {
        // 3×1 row, mine at the right end. Revealing the left cell floods the two
        // safe cells (a 0 then its bordering 1) and clears the board.
        let t = BoundedSquareTopology(width: 3, height: 1)
        var game = Game(topology: t, mines: [Coord(2, 0)])
        var rng = SeededRNG(seed: 1)
        game.reveal(Coord(0, 0), using: &rng)
        XCTAssertEqual(game.status, .won)
        XCTAssertEqual(game.revealedSafeCount, game.safeCellCount)
        XCTAssertEqual(game.progress, 1.0, accuracy: 1e-9)
    }

    /// Partial progress: revealing one numbered cell, then stepping on a mine,
    /// leaves progress strictly between 0 and 1, and the mine isn't counted.
    func testLossLeavesPartialProgress() {
        // 5×1 row with mines at both ends. Revealing an interior cell shows a
        // single "1" (its neighbours include a mine, so no cascade), leaving
        // safe cells unrevealed; then step on a mine to lose.
        let t = BoundedSquareTopology(width: 5, height: 1)
        var game = Game(topology: t, mines: [Coord(0, 0), Coord(4, 0)])
        var rng = SeededRNG(seed: 1)
        game.reveal(Coord(1, 0), using: &rng)  // a "1" next to the left mine
        XCTAssertEqual(game.status, .playing)
        XCTAssertEqual(game.revealedSafeCount, 1)

        game.reveal(Coord(0, 0), using: &rng)  // step on a mine
        XCTAssertEqual(game.status, .lost)
        XCTAssertGreaterThan(game.progress, 0)
        XCTAssertLessThan(game.progress, 1.0)
        // The mine reveal must not have counted as safe progress.
        XCTAssertEqual(game.revealedSafeCount, 1)
    }
}
