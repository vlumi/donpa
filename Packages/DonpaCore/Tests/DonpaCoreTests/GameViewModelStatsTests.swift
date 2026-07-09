import XCTest

@testable import DonpaCore

/// The stat-accuracy behaviour of `GameViewModel`: the no-flag / no-chord purity
/// bits and the chord/flag counters that feed the lifetime stats. Split from
/// `GameViewModelTests` (which covers the state machine) — these guard the rule
/// that a NO-OP input never counts as an action.
@MainActor
final class GameViewModelStatsTests: XCTestCase {

    /// Start a game with a safe first reveal at the origin (mines avoid the first
    /// click), so the board is `.playing` with a known mine layout.
    private func startedGame(_ config: GameConfig = .beginner) async -> GameViewModel {
        let vm = GameViewModel(config: config)
        vm.reveal(Coord(0, 0))
        await vm.awaitPendingWork()
        return vm
    }

    /// A cell that's still hidden after the opening reveal.
    private func aHiddenCell(_ vm: GameViewModel) -> Coord {
        for c in vm.game.board.allCoords where vm.game.board[c].state == .hidden {
            return c
        }
        XCTFail("no hidden cell after the opening reveal")
        return Coord(0, 0)
    }

    /// The purity bits start clean; flags LATCH on first placement. Chord stats
    /// count ONLY a chord that actually acts — the UI routes every tap on a
    /// revealed cell through `chord`, so no-op taps (a hidden cell, a revealed
    /// 0-cell) must not inflate the count or burn the no-chord feat.
    func testPurityBitsLatchAndChordCounts() async {
        let vm = await startedGame()
        XCTAssertFalse(vm.usedFlagEver, "clean at start")
        XCTAssertFalse(vm.usedChordEver)
        XCTAssertEqual(vm.chordsThisGame, 0)

        let target = aHiddenCell(vm)
        vm.toggleFlag(target)
        vm.toggleFlag(target)  // unflag — still "used flags"
        XCTAssertTrue(vm.usedFlagEver, "latches on first placement, not cleared by unflag")

        // No-op chords: a hidden cell, and the revealed 0 under the first click.
        vm.chord(aHiddenCell(vm))
        vm.chord(Coord(0, 0))
        await vm.awaitPendingWork()
        XCTAssertFalse(vm.usedChordEver, "no-op taps must not count as chording")
        XCTAssertEqual(vm.chordsThisGame, 0)

        // A real chord: flag every mine neighbour of a suitable revealed number,
        // then chord it — this one counts.
        guard let (number, mines) = chordableNumber(vm) else {
            return XCTFail("no chordable number on this board")
        }
        for m in mines { vm.toggleFlag(m) }
        vm.chord(number)
        await vm.awaitPendingWork()
        XCTAssertTrue(vm.usedChordEver, "an acting chord latches")
        XCTAssertEqual(vm.chordsThisGame, 1)
    }

    /// A revealed number whose hidden neighbours include all its mines (so exact
    /// flagging is possible) and at least one safe cell (so the chord will act).
    private func chordableNumber(_ vm: GameViewModel) -> (Coord, [Coord])? {
        let board = vm.game.board
        for c in board.allCoords
        where board[c].state == .revealed && board[c].adjacentMines > 0 {
            let ns = board.topology.neighbors(of: c)
            let hiddenMines = ns.filter { board[$0].state == .hidden && board[$0].isMine }
            let hiddenSafe = ns.filter { board[$0].state == .hidden && !board[$0].isMine }
            guard hiddenMines.count == board[c].adjacentMines, !hiddenSafe.isEmpty else {
                continue
            }
            return (c, hiddenMines)
        }
        return nil
    }

    /// Flagging a revealed cell is a no-op all the way down: no latch, and no
    /// revision bump (a bump would schedule a full-board autosave + redraw for
    /// every stray right-click on opened ground).
    /// A "?" mark is external memory too, so placing one violates Bare Hands
    /// exactly like a flag — even though it never counts as a flag elsewhere.
    func testQuestionMarkViolatesBareHands() async {
        let vm = await startedGame()
        XCTAssertFalse(vm.usedFlagEver, "clean at start")
        let target = aHiddenCell(vm)
        vm.toggleFlag(target, useQuestionMarks: true)  // → flagged
        vm.toggleFlag(target, useQuestionMarks: true)  // → questioned
        XCTAssertEqual(vm.game.board[target].state, .questioned)
        XCTAssertTrue(vm.usedFlagEver, "a ? counts as using external memory")
        // But it is NOT a placed flag for the flag-count stat.
        XCTAssertEqual(
            vm.flagsPlacedThisGame, 1, "only the flag step counted, not the ? step")
    }

    func testFlaggingARevealedCellChangesNothing() async {
        let vm = await startedGame()
        let before = vm.revision
        vm.toggleFlag(Coord(0, 0))  // the revealed first-click cell
        XCTAssertEqual(vm.revision, before, "no state change → no bump")
        XCTAssertFalse(vm.usedFlagEver)
        XCTAssertEqual(vm.flagsPlacedThisGame, 0)
    }

    /// A new game resets the purity bits to clean; a RESTORE defaults them to
    /// violated (a resumed game can't prove a clean run, so it can't earn the feat).
    func testPurityBitsResetOnNewGameAndViolatedOnRestore() async {
        let vm = await startedGame()
        vm.toggleFlag(aHiddenCell(vm))
        XCTAssertTrue(vm.usedFlagEver)

        vm.newGame()
        XCTAssertFalse(vm.usedFlagEver, "a fresh game is clean")
        XCTAssertFalse(vm.usedChordEver)
        XCTAssertEqual(vm.chordsThisGame, 0)

        // Restore defaults to violated (deny over false-award).
        let started = await startedGame()
        let snapshot = started.snapshot()!
        vm.restore(from: snapshot)
        XCTAssertTrue(vm.usedFlagEver, "restore can't prove a clean run → violated")
        XCTAssertTrue(vm.usedChordEver)
    }

    /// The forced-guess wiring: analysis of a coin-flip position reaches the
    /// host's `onForcedGuess` with the exact odds, the survived flag, and the
    /// captured config (the engine itself is covered by `GuessOddsTests`).
    func testForcedGuessReportsThroughHook() async {
        let vm = GameViewModel(config: .beginner)
        // The canonical sealed coin flip (see GuessOddsTests) as the PRE state.
        let topo = BoundedSquareTopology(width: 5, height: 3)
        let pocket: Set<Coord> = [Coord(0, 2), Coord(1, 2)]
        let mines: Set<Coord> = [
            Coord(0, 1), Coord(1, 1), Coord(2, 1), Coord(2, 2), Coord(0, 2),
        ]
        var pre = Game(topology: topo, mines: mines)
        for c in topo.allCoords() where !mines.contains(c) && !pocket.contains(c) {
            pre.reveal(c)
        }

        let reported = expectation(description: "forced guess reported")
        vm.onForcedGuess = { config, survival, survived in
            XCTAssertEqual(config, .beginner, "the config rides along")
            XCTAssertEqual(survival, 0.5, accuracy: 1e-9)
            XCTAssertTrue(survived)
            reported.fulfill()
        }
        vm.reportGuess(survived: true) { GuessOdds.analyze(pre, clicked: Coord(1, 2)) }
        await fulfillment(of: [reported], timeout: 5)
    }

    /// The clock's 0.1s tick publisher drives the displayed time — pump the run
    /// loop long enough for at least one tick to land after the opening reveal.
    func testClockTicksWhileRunning() {
        let vm = GameViewModel(config: .beginner)
        vm.reveal(Coord(0, 0))
        let beat = expectation(description: "run loop pumped")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { beat.fulfill() }
        wait(for: [beat], timeout: 3)  // pumps the main run loop → the timer fires
        XCTAssertGreaterThan(vm.clock.elapsedCentiseconds, 0)
    }
}
