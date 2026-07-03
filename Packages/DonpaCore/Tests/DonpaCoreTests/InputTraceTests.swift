import XCTest

@testable import DonpaCore

/// The input-trace helper: off by default (no launch arg in tests), and the logging
/// path runs without side effects when enabled — also exercised through a traced
/// view-model action so the interpolated trace lines in the input paths execute.
@MainActor
final class InputTraceTests: XCTestCase {
    override func tearDown() {
        InputTrace.enabled = false
        super.tearDown()
    }

    func testDisabledByDefaultAndLogIsInert() {
        XCTAssertFalse(InputTrace.enabled, "tests launch without -donpa.inputtrace")
        InputTrace.log("never evaluated")  // guard path
    }

    func testEnabledLogsThroughTheInputPaths() async {
        InputTrace.enabled = true
        InputTrace.log("direct line")  // logging body

        // Run a traced game action end-to-end so the reveal/flag/gate trace
        // interpolations execute (newGame arms → reveal → gate on/off).
        let vm = GameViewModel(config: .beginner)
        vm.newGame()
        await vm.awaitPendingWork()
        vm.reveal(Coord(0, 0))
        await vm.awaitPendingWork()
        vm.toggleFlag(Coord(1, 1))
        vm.chord(Coord(0, 0))
        XCTAssertTrue(vm.game.status == .playing || vm.game.status == .won)
    }
}
