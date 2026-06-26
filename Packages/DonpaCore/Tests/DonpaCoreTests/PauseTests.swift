import XCTest

@testable import DonpaCore

@MainActor
final class PauseTests: XCTestCase {
    /// Reveal a safe cell to move the game into `.playing` (mines avoid the
    /// first click, so some reveal is always safe). Reveal computes off the main
    /// thread, so await it before inspecting the board.
    private func startedGame() async -> GameViewModel {
        let vm = GameViewModel(config: .beginner)
        vm.reveal(Coord(0, 0))
        await vm.awaitPendingWork()
        return vm
    }

    func testPauseOnlyWhilePlaying() async {
        let vm = GameViewModel(config: .beginner)
        vm.pause()  // .notStarted → no-op
        XCTAssertFalse(vm.isPaused)

        let playing = await startedGame()
        XCTAssertEqual(playing.status, .playing)
        playing.pause()
        XCTAssertTrue(playing.isPaused)
    }

    func testResumeClearsPaused() async {
        let vm = await startedGame()
        vm.pause()
        XCTAssertTrue(vm.isPaused)
        vm.resume()
        XCTAssertFalse(vm.isPaused)
    }

    func testDoublePauseIsIdempotent() async {
        let vm = await startedGame()
        vm.pause()
        vm.pause()
        XCTAssertTrue(vm.isPaused)
        vm.resume()
        XCTAssertFalse(vm.isPaused)
    }

    func testNewGameClearsPaused() async {
        let vm = await startedGame()
        vm.pause()
        vm.newGame()
        XCTAssertFalse(vm.isPaused)
        XCTAssertEqual(vm.elapsedCentiseconds, 0)
    }

    func testPauseDoesNotEndOrAlterTheGame() async {
        let vm = await startedGame()
        let before = vm.game.revealedSafeCount
        vm.pause()
        XCTAssertEqual(vm.status, .playing, "pause freezes, never finishes the game")
        XCTAssertEqual(vm.game.revealedSafeCount, before)
    }
}
