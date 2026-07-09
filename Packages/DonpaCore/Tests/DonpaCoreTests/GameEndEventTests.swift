import XCTest

@testable import DonpaCore

/// A1 of the progression spec: the game-end event and its reveal-action clock.
@MainActor
final class GameEndEventTests: XCTestCase {
    private func startedGame(_ config: GameConfig = .beginner) async -> GameViewModel {
        let vm = GameViewModel(config: config)
        vm.reveal(Coord(0, 0))
        await vm.awaitPendingWork()
        return vm
    }

    private func aHiddenCell(_ vm: GameViewModel) -> Coord {
        for c in vm.game.board.allCoords where vm.game.board[c].state == .hidden {
            return c
        }
        XCTFail("no hidden cell after the opening reveal")
        return Coord(0, 0)
    }

    func testRevealActionsCountRealActionsOnly() async {
        let vm = await startedGame()
        XCTAssertEqual(vm.revealActionsThisGame, 1)  // the opening reveal
        // A flag is not a reveal-type action.
        vm.toggleFlag(aHiddenCell(vm))
        await vm.awaitPendingWork()
        XCTAssertEqual(vm.revealActionsThisGame, 1)
        // Revealing a flagged cell no-ops (state != .hidden) — no tick.
        let flagged = vm.game.board.flaggedCoords.first!
        vm.reveal(flagged)
        await vm.awaitPendingWork()
        XCTAssertEqual(vm.revealActionsThisGame, 1)
        vm.toggleFlag(flagged)  // clear it; a real reveal ticks
        vm.reveal(flagged)
        await vm.awaitPendingWork()
        XCTAssertEqual(vm.revealActionsThisGame, 2)
    }

    func testNewGameResetsAndRestorePoisonsTheClock() async {
        let vm = await startedGame()
        XCTAssertEqual(vm.revealActionsThisGame, 1)
        guard let snapshot = vm.snapshot() else { return XCTFail("no snapshot") }
        vm.newGame()
        XCTAssertEqual(vm.revealActionsThisGame, 0)
        vm.restore(from: snapshot)
        // Pre-save actions are unknowable → a resumed game can never look like
        // "the second reveal" to a momentary feat.
        XCTAssertEqual(vm.revealActionsThisGame, GameViewModel.restoredActionsPoison)
    }

    func testGameEndEmitsTheEvent() async throws {
        // A 1-mine board: reveal everything safe → win deterministically.
        let vm = GameViewModel(config: .grid(.xs, .easy, .flat))
        var events: [GameEndEvent] = []
        vm.onGameEnd = { events.append($0) }
        vm.reveal(Coord(0, 0))
        await vm.awaitPendingWork()
        // Sweep every remaining hidden cell except the mines.
        for c in vm.game.board.allCoords
        where vm.game.board[c].state == .hidden && !vm.game.board[c].isMine {
            vm.reveal(c)
            await vm.awaitPendingWork()
            if vm.status == .won { break }
        }
        XCTAssertEqual(vm.status, .won)
        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertTrue(event.won)
        XCTAssertEqual(event.config, .grid(.xs, .easy, .flat))
        XCTAssertEqual(event.progress, 1)
        XCTAssertGreaterThan(event.revealActions, 0)
        XCTAssertLessThan(event.revealActions, GameViewModel.restoredActionsPoison)
    }

    /// The eager pre-arm after newGame (computeOffMain's default afterApply):
    /// mines are placed off-main before any tap.
    func testNewGamePreArmsTheBoard() async {
        let vm = GameViewModel(config: .beginner)
        vm.newGame()
        await vm.awaitPendingWork()
        XCTAssertEqual(vm.status, .notStarted)
        XCTAssertFalse(vm.game.board.mineCoords.isEmpty, "eager arming placed the mines")
    }
}
