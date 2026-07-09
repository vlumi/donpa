import XCTest

@testable import DonpaCore

/// The opt-in "?" flag cycle (hidden → flag → "?" → clear). A "?" is a note, not
/// a claim: it never counts as a flag toward the counter, chording, or over-flag,
/// but it DOES break Bare Hands (external memory) and it IS diggable.
final class QuestionFlagTests: XCTestCase {

    // MARK: Cycle

    func testCycleWithQuestionMarksOn() {
        var game = Game(difficulty: .beginner)
        let c = Coord(0, 0)
        XCTAssertEqual(game.board[c].state, .hidden)
        game.toggleFlag(c, useQuestionMarks: true)
        XCTAssertEqual(game.board[c].state, .flagged)
        game.toggleFlag(c, useQuestionMarks: true)
        XCTAssertEqual(game.board[c].state, .questioned)
        game.toggleFlag(c, useQuestionMarks: true)
        XCTAssertEqual(game.board[c].state, .hidden, "the ? cycles back to clear")
    }

    func testCycleWithQuestionMarksOffIsPlainToggle() {
        var game = Game(difficulty: .beginner)
        let c = Coord(0, 0)
        game.toggleFlag(c, useQuestionMarks: false)
        XCTAssertEqual(game.board[c].state, .flagged)
        game.toggleFlag(c, useQuestionMarks: false)
        XCTAssertEqual(game.board[c].state, .hidden, "no ? step when the setting is off")
    }

    // MARK: A "?" is not a flag

    func testQuestionDoesNotCountTowardTheMineCounter() {
        var game = Game(difficulty: .beginner)
        let before = game.flagsRemaining
        game.toggleFlag(Coord(0, 0), useQuestionMarks: true)  // → flagged
        XCTAssertEqual(game.flagsRemaining, before - 1, "a flag decrements the counter")
        game.toggleFlag(Coord(0, 0), useQuestionMarks: true)  // → questioned
        XCTAssertEqual(
            game.flagsRemaining, before, "a ? is not a claim — the counter returns")
    }

    func testQuestionDoesNotSatisfyAChord() {
        // A revealed number with all its mine-neighbours marked "?" instead of
        // flagged must NOT chord (only real flags satisfy a number).
        var game = Game(difficulty: .beginner)
        var rng = SeededRNG(seed: 9)
        game.reveal(Coord(4, 4), using: &rng)
        guard let target = revealedNumberWithAllMineNeighborsKnown(in: game) else {
            XCTFail("no suitable numbered cell for seed")
            return
        }
        let mineNeighbors = neighbors(of: target, in: game).filter { game.board[$0].isMine }
        // Mark them as "?" (flag → ?), not flags.
        for m in mineNeighbors {
            game.toggleFlag(m, useQuestionMarks: true)
            game.toggleFlag(m, useQuestionMarks: true)
            XCTAssertEqual(game.board[m].state, .questioned)
        }
        let hiddenBefore = neighbors(of: target, in: game).filter {
            game.board[$0].state == .hidden
        }
        game.chord(target, using: &rng)
        for h in hiddenBefore {
            XCTAssertEqual(
                game.board[h].state, .hidden, "a ? must not satisfy the number for a chord")
        }
    }

    func testChordOpensAQuestionedNeighbor() {
        // A "?" does not protect a cell: a valid chord (satisfied by real flags)
        // opens a "?"-marked neighbour just like a hidden one.
        var game = Game(difficulty: .beginner)
        var rng = SeededRNG(seed: 9)
        game.reveal(Coord(4, 4), using: &rng)
        guard let target = revealedNumberWithAllMineNeighborsKnown(in: game) else {
            XCTFail("no suitable numbered cell for seed")
            return
        }
        // Flag the mines (real flags → chord will fire).
        for m in neighbors(of: target, in: game).filter({ game.board[$0].isMine }) {
            game.toggleFlag(m)
        }
        // Mark one safe hidden neighbour as "?".
        guard
            let safe = neighbors(of: target, in: game).first(where: {
                game.board[$0].state == .hidden && !game.board[$0].isMine
            })
        else {
            XCTFail("no safe hidden neighbour to question")
            return
        }
        game.toggleFlag(safe, useQuestionMarks: true)
        game.toggleFlag(safe, useQuestionMarks: true)
        XCTAssertEqual(game.board[safe].state, .questioned)

        game.chord(target, using: &rng)
        XCTAssertEqual(game.board[safe].state, .revealed, "a chord opens a ? neighbour")
    }

    func testDiggingAQuestionedCellReveals() {
        var game = Game(difficulty: .beginner)
        var rng = SeededRNG(seed: 3)
        game.reveal(Coord(4, 4), using: &rng)  // arm + open a region
        // Find a still-hidden safe cell, mark it "?", then dig it.
        guard
            let safe = game.board.allCoords.first(where: {
                game.board[$0].state == .hidden && !game.board[$0].isMine
            })
        else {
            XCTFail("no hidden safe cell")
            return
        }
        game.toggleFlag(safe, useQuestionMarks: true)
        game.toggleFlag(safe, useQuestionMarks: true)
        XCTAssertEqual(game.board[safe].state, .questioned)
        game.reveal(safe, using: &rng)
        XCTAssertEqual(game.board[safe].state, .revealed, "a ? cell is diggable")
    }

    // MARK: Save round-trip

    func testQuestionedCellsSurviveSaveRestore() throws {
        var game = Game(difficulty: .beginner)
        var rng = SeededRNG(seed: 7)
        game.reveal(Coord(4, 4), using: &rng)
        // Place one flag and one "?".
        let hidden = game.board.allCoords.filter { game.board[$0].state == .hidden }
        guard hidden.count >= 2 else {
            XCTFail("need two hidden cells")
            return
        }
        game.toggleFlag(hidden[0])  // flag
        game.toggleFlag(hidden[1], useQuestionMarks: true)  // flag
        game.toggleFlag(hidden[1], useQuestionMarks: true)  // → ?
        XCTAssertEqual(game.board[hidden[1]].state, .questioned)

        let snapshot = try XCTUnwrap(
            GameSnapshot(game: game, config: .beginner, elapsedCentiseconds: 0))
        let restored = snapshot.makeGame()
        XCTAssertEqual(restored.board[hidden[0]].state, .flagged)
        XCTAssertEqual(restored.board[hidden[1]].state, .questioned)
        XCTAssertEqual(
            restored.flagsRemaining, game.flagsRemaining,
            "the ? doesn't skew the restored counter")
    }

    // MARK: Test helpers (mirrors ChordTests)

    private func neighbors(of c: Coord, in game: Game) -> [Coord] {
        game.board.topology.neighbors(of: c)
    }

    private func revealedNumberWithAllMineNeighborsKnown(in game: Game) -> Coord? {
        game.board.allCoords.first { c in
            guard game.board[c].state == .revealed, game.board[c].adjacentMines > 0 else {
                return false
            }
            let ns = neighbors(of: c, in: game)
            let hiddenNs = ns.filter { game.board[$0].state == .hidden }
            let mineNs = ns.filter { game.board[$0].isMine }
            // All hidden neighbours are mines (so flagging exactly the mines is
            // safe) and at least one hidden non-... actually: we need at least one
            // safe hidden neighbour to open, and the mines fully known.
            return !mineNs.isEmpty && hiddenNs.count > mineNs.count
                && mineNs.allSatisfy { game.board[$0].state == .hidden }
        }
    }
}
