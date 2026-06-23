import XCTest

@testable import DonpaCore

final class GameSnapshotTests: XCTestCase {
    /// A mid-game board: reveal a corner, flag a couple of cells.
    private func playingGame() -> (Game, GameConfig) {
        let config = GameConfig.classic(.beginner)
        var game = Game(config: config)
        game.reveal(Coord(0, 0))  // places mines, opens a region → .playing
        XCTAssertEqual(game.status, .playing)
        // Flag the first two mines we can find, to exercise flagged state.
        let mines = Array(game.board.mineCoords).prefix(2)
        for m in mines { game.toggleFlag(m) }
        return (game, config)
    }

    func testSnapshotIsNilUnlessPlaying() {
        let config = GameConfig.classic(.beginner)
        let fresh = Game(config: config)
        XCTAssertNil(
            GameSnapshot(game: fresh, config: config, elapsedCentiseconds: 0),
            "a not-started game isn't worth saving")
    }

    func testRoundTripPreservesState() throws {
        let (game, config) = playingGame()
        let snap = try XCTUnwrap(
            GameSnapshot(game: game, config: config, elapsedCentiseconds: 1234))

        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(GameSnapshot.self, from: data)
        let restored = decoded.makeGame()

        XCTAssertEqual(restored.status, game.status)
        XCTAssertEqual(restored.board.mineCoords, game.board.mineCoords)
        XCTAssertEqual(restored.board.revealedCoords, game.board.revealedCoords)
        XCTAssertEqual(restored.board.flaggedCoords, game.board.flaggedCoords)
        XCTAssertEqual(restored.revealedSafeCount, game.revealedSafeCount)
        XCTAssertEqual(restored.mineCount, game.mineCount)
        XCTAssertEqual(decoded.elapsedCentiseconds, 1234)
        // Adjacency must be recomputed identically, so play can continue.
        for c in game.board.allCoords {
            XCTAssertEqual(restored.board[c].adjacentMines, game.board[c].adjacentMines)
        }
    }

    func testRestoredGameRemainsPlayable() throws {
        let (game, config) = playingGame()
        let snap = try XCTUnwrap(GameSnapshot(game: game, config: config, elapsedCentiseconds: 0))
        var restored = snap.makeGame()
        // A safe, still-hidden cell can still be revealed after restore.
        let safeHidden = restored.board.allCoords.first {
            restored.board[$0].state == .hidden && !restored.board[$0].isMine
        }
        let c = try XCTUnwrap(safeHidden)
        let before = restored.revealedSafeCount
        restored.reveal(c)
        XCTAssertGreaterThan(restored.revealedSafeCount, before)
    }

    func testModernConfigRoundTrips() throws {
        let config = GameConfig.modern(.small, .normal)
        var game = Game(config: config)
        game.reveal(Coord(0, 0))
        let snap = try XCTUnwrap(GameSnapshot(game: game, config: config, elapsedCentiseconds: 0))
        let decoded = try JSONDecoder().decode(
            GameSnapshot.self, from: try JSONEncoder().encode(snap))
        XCTAssertEqual(decoded.config, config, "tagged config rebuilds the right topology")
        XCTAssertEqual(decoded.makeGame().board.cellCount, game.board.cellCount)
    }

    func testCoordEncodesAsCompactArray() throws {
        let data = try JSONEncoder().encode(Coord(3, 7))
        XCTAssertEqual(String(data: data, encoding: .utf8), "[3,7]")
    }
}
