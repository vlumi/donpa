import XCTest

@testable import DonpaCore

/// The forced-guess odds engine, exercised on the three canonical sealed-pocket
/// shapes (1/2, 1/3, 1/4) plus the coupling, certainty and bail-out edges.
final class GuessOddsTests: XCTestCase {
    /// Build a playing game with a fixed layout and everything revealed except
    /// the mines and the given pocket cells (revealing cell by cell — flood fill
    /// takes care of the rest; a direct reveal of a numbered cell just opens it).
    private func position(
        width: Int, height: Int, mines: Set<Coord>, pocket: Set<Coord>
    ) -> Game {
        let topo = BoundedSquareTopology(width: width, height: height)
        var game = Game(topology: topo, mines: mines)
        for c in topo.allCoords() where !mines.contains(c) && !pocket.contains(c) {
            game.reveal(c)
        }
        return game
    }

    // MARK: The three canonical pockets

    /// Corner pair sealed by found mines, one mine left: the classic coin flip.
    ///
    ///     2  3  2  1  ·
    ///     M  M  M  2  ·
    ///     ?  ?  M  2  ·
    func testCoinFlip() {
        let pocket: Set<Coord> = [Coord(0, 2), Coord(1, 2)]
        let game = position(
            width: 5, height: 3,
            mines: [Coord(0, 1), Coord(1, 1), Coord(2, 1), Coord(2, 2), Coord(0, 2)],
            pocket: pocket)
        for c in pocket {
            let v = GuessOdds.analyze(game, clicked: c)
            XCTAssertNotNil(v)
            XCTAssertTrue(v!.forced)
            XCTAssertEqual(v!.survival, 0.5, accuracy: 1e-9)
        }
    }

    /// Corner pocket of three cells that only a single number ("the 6") sees:
    /// two mines among three, every placement equally likely.
    ///
    ///     2  2  1  ·  ·
    ///     M  M  2  1  ·
    ///     ?  6  M  2  ·
    ///     ?  ?  M  2  ·
    func testLongShot() {
        let pocket: Set<Coord> = [Coord(0, 2), Coord(0, 3), Coord(1, 3)]
        let game = position(
            width: 5, height: 4,
            mines: [
                Coord(0, 1), Coord(1, 1), Coord(2, 2), Coord(2, 3),  // the seal
                Coord(0, 2), Coord(1, 3),  // the pocket's actual two mines
            ],
            pocket: pocket)
        // Sanity: the seer really shows 6 (4 sealed mines + 2 pocket mines).
        XCTAssertEqual(game.board[Coord(1, 2)].adjacentMines, 6)
        for c in pocket {
            let v = GuessOdds.analyze(game, clicked: c)
            XCTAssertNotNil(v)
            XCTAssertTrue(v!.forced)
            XCTAssertEqual(v!.survival, 1.0 / 3.0, accuracy: 1e-9)
        }
    }

    /// Fully sealed 2×2 with three mines left: no number sees inside, the mine
    /// counter is the only clue — the pocket is pure "interior" to the engine.
    ///
    ///     2  3  2  1  ·
    ///     M  M  M  2  ·
    ///     ?  ?  M  3  ·
    ///     ?  ?  M  2  ·
    func testMiracle() {
        let pocket: Set<Coord> = [Coord(0, 2), Coord(1, 2), Coord(0, 3), Coord(1, 3)]
        let game = position(
            width: 5, height: 4,
            mines: [
                Coord(0, 1), Coord(1, 1), Coord(2, 1), Coord(2, 2), Coord(2, 3),  // the seal
                Coord(0, 2), Coord(1, 2), Coord(0, 3),  // three of the four
            ],
            pocket: pocket)
        for c in pocket {
            let v = GuessOdds.analyze(game, clicked: c)
            XCTAssertNotNil(v)
            XCTAssertTrue(v!.forced)
            XCTAssertEqual(v!.survival, 0.25, accuracy: 1e-9)
        }
    }

    // MARK: Frontier–interior coupling

    /// One revealed "1" and a big anonymous rest: the frontier five share one
    /// mine (survive 4/5), the ten interior cells share the leftover (survive
    /// 9/10) — and with no certain cell anywhere, even the good-odds interior
    /// click is a forced guess.
    func testFrontierAndInteriorOdds() {
        let topo = BoundedSquareTopology(width: 4, height: 4)
        var game = Game(topology: topo, mines: [Coord(0, 0), Coord(3, 3)])
        // A lone number with no zero-flood: reveal just (1,0), which sees the
        // corner mine.
        game.reveal(Coord(1, 0))
        XCTAssertEqual(game.board.revealedCoords, [Coord(1, 0)])

        // Frontier = its five hidden neighbours, exactly one of which is a mine.
        let frontier = GuessOdds.analyze(game, clicked: Coord(0, 1))
        XCTAssertEqual(frontier?.forced, true)
        XCTAssertEqual(frontier!.survival, 4.0 / 5.0, accuracy: 1e-9)

        // Interior = the other 10 hidden cells sharing the one leftover mine.
        let interior = GuessOdds.analyze(game, clicked: Coord(3, 3))
        XCTAssertEqual(interior?.forced, true)
        XCTAssertEqual(interior!.survival, 9.0 / 10.0, accuracy: 1e-9)
    }

    // MARK: Certainty means not forced

    /// The number pins the mine and the global count clears the rest: a certain
    /// cell exists, so nothing about this position is a forced guess.
    func testNotForcedWhenACellIsCertain() {
        let topo = BoundedSquareTopology(width: 5, height: 1)
        var game = Game(topology: topo, mines: [Coord(1, 0)])
        game.reveal(Coord(3, 0))  // floods right, fringes at the "1" next to the mine
        XCTAssertEqual(game.board[Coord(2, 0)].state, .revealed)
        XCTAssertEqual(game.board[Coord(0, 0)].state, .hidden)

        let v = GuessOdds.analyze(game, clicked: Coord(0, 0))
        XCTAssertEqual(v?.forced, false)
        XCTAssertEqual(v!.survival, 1.0, accuracy: 1e-9)
    }

    /// Flags are marks, not facts: a (wrong) flag on the pocket changes nothing —
    /// the engine reads the same unknowns either way.
    func testFlagsAreIgnored() {
        let pocket: Set<Coord> = [Coord(0, 2), Coord(1, 2)]
        var game = position(
            width: 5, height: 3,
            mines: [Coord(0, 1), Coord(1, 1), Coord(2, 1), Coord(2, 2), Coord(0, 2)],
            pocket: pocket)
        game.toggleFlag(Coord(1, 2))  // flag the SAFE cell, wrongly

        let v = GuessOdds.analyze(game, clicked: Coord(0, 2))
        XCTAssertEqual(v?.forced, true)
        XCTAssertEqual(v!.survival, 0.5, accuracy: 1e-9)
    }

    // MARK: Chords gamble on the whole opened set

    /// The long-shot pocket, played chord-style: flag the four sealed mines and
    /// two of the three pocket cells — the chord at the "6" then opens exactly
    /// the remaining pocket cell, which is safe only in the layout where the two
    /// flagged cells hold both mines: survive 1 in 3.
    func testChordOnLongShotPocket() {
        var game = position(
            width: 5, height: 4,
            mines: [
                Coord(0, 1), Coord(1, 1), Coord(2, 2), Coord(2, 3),
                Coord(0, 2), Coord(1, 3),
            ],
            pocket: [Coord(0, 2), Coord(0, 3), Coord(1, 3)])
        for f in [Coord(0, 1), Coord(1, 1), Coord(2, 2), Coord(2, 3), Coord(0, 2), Coord(0, 3)] {
            game.toggleFlag(f)
        }
        XCTAssertTrue(game.canChord(Coord(1, 2)), "six flags around the 6")

        let v = GuessOdds.analyzeChord(game, at: Coord(1, 2))
        XCTAssertEqual(v?.forced, true)
        XCTAssertEqual(v!.survival, 1.0 / 3.0, accuracy: 1e-9)
    }

    /// A chord whose opened set spans several uncertain cells: flag one of the
    /// "1"-frontier's five cells and chord — all four remaining open at once, all
    /// safe only when the flagged cell is the mine: survive 1 in 5.
    func testChordSetProbability() {
        let topo = BoundedSquareTopology(width: 4, height: 4)
        var game = Game(topology: topo, mines: [Coord(0, 0), Coord(3, 3)])
        game.reveal(Coord(1, 0))  // the "1"
        game.toggleFlag(Coord(0, 0))
        XCTAssertTrue(game.canChord(Coord(1, 0)))

        let v = GuessOdds.analyzeChord(game, at: Coord(1, 0))
        XCTAssertEqual(v?.forced, true)
        XCTAssertEqual(v!.survival, 1.0 / 5.0, accuracy: 1e-9)
    }

    /// An impossible opened set (it must contain a mine) reads survival 0 — and
    /// flags never create certainty: even with every ACTUAL mine correctly
    /// flagged, the opened pocket cell still reads its honest layout odds (a
    /// flag is a mark, not a fact).
    func testChordImpossibleSetAndFlagsCreateNoCertainty() {
        var game = position(
            width: 5, height: 4,
            mines: [
                Coord(0, 1), Coord(1, 1), Coord(2, 2), Coord(2, 3),
                Coord(0, 2), Coord(1, 3),
            ],
            pocket: [Coord(0, 2), Coord(0, 3), Coord(1, 3)])
        // No flags at all: the chord at the 6 would open the four PINNED seal
        // mines along with the pocket — survival exactly 0.
        let doomed = GuessOdds.analyzeChord(game, at: Coord(1, 2))
        XCTAssertEqual(doomed!.survival, 0, accuracy: 1e-12)

        // Flag all six actual mines (a perfect player): the chord opens just the
        // safe pocket cell — but the flags prove nothing, so it reads the
        // pocket's honest 1-in-3, not 1.0.
        for f in game.board.mineCoords { game.toggleFlag(f) }
        let flagged = GuessOdds.analyzeChord(game, at: Coord(1, 2))
        XCTAssertEqual(flagged?.forced, true)
        XCTAssertEqual(flagged!.survival, 1.0 / 3.0, accuracy: 1e-9)
    }

    // MARK: Bail-outs

    /// Boards past the analysis ceiling get no verdict at all.
    func testBailsOnHugeBoard() {
        let topo = BoundedSquareTopology(width: 128, height: 64)  // 8192 > maxCells
        var game = Game(topology: topo, mines: [Coord(0, 0)])
        game.reveal(Coord(64, 32))
        XCTAssertNil(GuessOdds.analyze(game, clicked: Coord(1, 0)))
    }

    /// A frontier component too big to enumerate gets no verdict (never an
    /// estimate). Two rows: the top revealed cell-by-cell, the bottom one long
    /// connected hidden strip.
    func testBailsOnOversizeComponent() {
        let width = GuessOdds.maxComponentCells + 5
        let topo = BoundedSquareTopology(width: width, height: 2)
        let mines = Set((0..<width).filter { $0.isMultiple(of: 2) }.map { Coord($0, 1) })
        var game = Game(topology: topo, mines: mines)
        for x in 0..<width { game.reveal(Coord(x, 0)) }
        XCTAssertNil(GuessOdds.analyze(game, clicked: Coord(1, 1)))
    }

    /// Before the first click there is nothing to guess about.
    func testNoVerdictBeforeFirstReveal() {
        let game = Game(config: .beginner)
        XCTAssertNil(GuessOdds.analyze(game, clicked: Coord(4, 4)))
    }
}
