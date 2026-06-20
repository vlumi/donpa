import WrapsweeperCore
import XCTest

@testable import WrapsweeperKit

@MainActor
final class ScoreboardTests: XCTestCase {
    private let suiteName = "wrapsweeper.tests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testEmptyHasNoRecords() {
        let board = Scoreboard(defaults: defaults)
        XCTAssertNil(board.best(for: .beginner))
        XCTAssertTrue(
            board.isNewRecord(999, for: .beginner), "any time is a record on an empty board")
    }

    func testFirstSubmitBecomesRecord() {
        let board = Scoreboard(defaults: defaults)
        XCTAssertTrue(board.submit(42, for: .beginner))
        XCTAssertEqual(board.best(for: .beginner)?.seconds, 42)
    }

    func testFasterTimeReplacesRecord() {
        let board = Scoreboard(defaults: defaults)
        board.submit(42, for: .beginner)
        XCTAssertTrue(board.isNewRecord(30, for: .beginner))
        XCTAssertTrue(board.submit(30, for: .beginner))
        XCTAssertEqual(board.best(for: .beginner)?.seconds, 30)
    }

    func testSlowerTimeIsRejected() {
        let board = Scoreboard(defaults: defaults)
        board.submit(30, for: .beginner)
        XCTAssertFalse(board.isNewRecord(45, for: .beginner))
        XCTAssertFalse(board.submit(45, for: .beginner), "a slower time must not be recorded")
        XCTAssertEqual(board.best(for: .beginner)?.seconds, 30)
    }

    func testEqualTimeIsNotABetterRecord() {
        let board = Scoreboard(defaults: defaults)
        board.submit(30, for: .beginner)
        XCTAssertFalse(board.isNewRecord(30, for: .beginner), "ties are not new records")
        XCTAssertFalse(board.submit(30, for: .beginner))
    }

    func testRecordsAreIndependentPerDifficulty() {
        let board = Scoreboard(defaults: defaults)
        board.submit(30, for: .beginner)
        XCTAssertNil(board.best(for: .expert))
        XCTAssertTrue(board.submit(120, for: .expert))
        XCTAssertEqual(board.best(for: .beginner)?.seconds, 30)
        XCTAssertEqual(board.best(for: .expert)?.seconds, 120)
    }

    func testRecordsPersistAcrossInstances() {
        let first = Scoreboard(defaults: defaults)
        first.submit(33, for: .intermediate)
        // A fresh instance over the same defaults should load the saved record.
        let second = Scoreboard(defaults: defaults)
        XCTAssertEqual(second.best(for: .intermediate)?.seconds, 33)
    }

    func testResetClearsEverythingAndPersists() {
        let board = Scoreboard(defaults: defaults)
        board.submit(30, for: .beginner)
        board.submit(120, for: .expert)
        board.reset()
        XCTAssertNil(board.best(for: .beginner))
        XCTAssertNil(board.best(for: .expert))
        // Reset must be durable, not just in-memory.
        let reloaded = Scoreboard(defaults: defaults)
        XCTAssertNil(reloaded.best(for: .beginner))
    }
}
