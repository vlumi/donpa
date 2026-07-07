import XCTest

@testable import DonpaCore

/// The Range's repair-based no-guess generator: every layout it returns must be
/// fully deduction-solvable, first-click-safe, and the right size.
final class PracticeBoardTests: XCTestCase {
    private struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { self.state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// Generate + verify one board: solvable without guessing, exact mine count,
    /// and the first-click neighbourhood untouched.
    private func verify(
        topology: any RectangularTopology, mineCount: Int, seed: UInt64,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        var rng = SeededRNG(seed: seed)
        let click = Coord(topology.width / 2, topology.height / 2)
        guard
            let mines = PracticeBoard.mines(
                topology: topology, mineCount: mineCount, firstClick: click, using: &rng)
        else {
            XCTFail("generation gave up", file: file, line: line)
            return
        }
        XCTAssertEqual(mines.count, mineCount, file: file, line: line)
        XCTAssertFalse(mines.contains(click), file: file, line: line)
        for n in topology.neighbors(of: click) {
            XCTAssertFalse(mines.contains(n), "safe zone", file: file, line: line)
        }
        var game = Game(topology: topology, mines: mines)
        var checkRNG = SeededRNG(seed: seed &+ 999)
        let result = Solver().solve(&game, firstClick: click, using: &checkRNG)
        XCTAssertTrue(result.solvedWithoutGuessing, "must be no-guess", file: file, line: line)
    }

    /// Practice density (12%) across the small board ladder, several seeds each —
    /// at ~50% raw guess rates on M this exercises the repair path constantly.
    func testGeneratesSolvableBoards() {
        for seed in UInt64(1)...4 {
            verify(topology: BoundedSquareTopology(width: 8, height: 8), mineCount: 8, seed: seed)
            verify(
                topology: BoundedSquareTopology(width: 16, height: 16), mineCount: 31, seed: seed)
            verify(
                topology: BoundedSquareTopology(width: 32, height: 32), mineCount: 123, seed: seed)
        }
    }

    /// The generator is topology-generic: hex and wrapped boards repair the same.
    func testGeneratesOnOtherTopologies() {
        verify(topology: HexTopology(width: 16, height: 16), mineCount: 31, seed: 7)
        verify(topology: WrappedSquareTopology(width: 16, height: 16), mineCount: 31, seed: 7)
    }

    /// The doorway picker: a flag qualifies only when it touches both the
    /// revealed outside and the hidden inside; with no such flag (or none at
    /// all) there is no door.
    func testDoorwaySelection() {
        let topo = BoundedSquareTopology(width: 3, height: 2)
        var game = Game(topology: topo, mines: [Coord(0, 0)])
        game.reveal(Coord(1, 0))  // a "1"; everything else stays hidden
        XCTAssertNil(PracticeBoard.doorway(in: game), "no flags → no door")

        game.toggleFlag(Coord(0, 0))  // touches the 1 (revealed) and (0,1) (hidden)
        XCTAssertEqual(PracticeBoard.doorway(in: game), Coord(0, 0))
    }

    /// An off-board first click yields nothing; near-saturated boards stress
    /// every repair path (flag-sealed doorways included) — the generator must
    /// terminate, and whatever it does return must verify as no-guess (nil is
    /// always acceptable; a lie never is).
    func testSaturatedBoardsTerminateAndNeverLie() {
        let topo = BoundedSquareTopology(width: 4, height: 4)
        var offRNG = SeededRNG(seed: 1)
        XCTAssertNil(
            PracticeBoard.mines(
                topology: topo, mineCount: 6, firstClick: Coord(99, 99), using: &offRNG))

        for seed in UInt64(0)..<12 {
            for mineCount in [6, 10, 14] {
                var rng = SeededRNG(seed: seed)
                guard
                    let layout = PracticeBoard.mines(
                        topology: topo, mineCount: mineCount, firstClick: Coord(1, 1),
                        using: &rng)
                else { continue }  // giving up is honest
                var game = Game(topology: topo, mines: layout)
                var check = SeededRNG(seed: seed &+ 5000)
                let result = Solver().solve(&game, firstClick: Coord(1, 1), using: &check)
                XCTAssertTrue(
                    result.solvedWithoutGuessing, "lied at seed \(seed), \(mineCount) mines")
            }
        }
    }
}

/// The worklist solver's defensive edges, reached via the internal resume API.
final class SolverResumeTests: XCTestCase {
    private struct FixedRNG: RandomNumberGenerator {
        mutating func next() -> UInt64 { 42 }
    }

    /// A WRONG flag makes rule 2 detonate: the solver must stop and report the
    /// loss instead of trusting its own flags blindly. (Unreachable in normal
    /// runs — the solver's flags are always sound — but the generator mutates
    /// boards mid-run, so the guard stays and stays tested.)
    func testWrongFlagLossIsReportedNotTrusted() {
        let topo = BoundedSquareTopology(width: 3, height: 2)
        var game = Game(topology: topo, mines: [Coord(0, 0)])
        game.reveal(Coord(1, 0))  // the "1" beside the mine
        game.toggleFlag(Coord(1, 1))  // WRONG flag: satisfies the 1 falsely
        var rng = FixedRNG()
        let (result, stuck) = Solver().continueTracked(
            &game, from: [Coord(1, 0)], using: &rng)
        XCTAssertEqual(result.status, .lost)
        XCTAssertFalse(result.solvedWithoutGuessing)
        XCTAssertTrue(stuck.isEmpty)
    }
}
