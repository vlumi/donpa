import XCTest

@testable import DonpaCore

/// The ASC wire contract — these IDs go permanent at the store release, so
/// the shape is locked here the way the achievement raw values are.
final class GameCenterMappingTests: XCTestCase {
    func testTwentySixDefinitions() {
        let ids = GameCenterMapping.allWireIDs
        XCTAssertEqual(ids.count, 26)  // 17 one-shots + 3 ladders × 3 steps
        XCTAssertEqual(ids.count, Set(ids).count, "wire IDs are unique")
        XCTAssertTrue(ids.allSatisfy { $0.hasPrefix("fi.misaki.donpa.") })
    }

    func testWireIDShapes() {
        XCTAssertEqual(GameCenterMapping.wireID(.winFirst), "fi.misaki.donpa.win.first")
        XCTAssertEqual(
            GameCenterMapping.wireID(.milesWins, tier: 1), "fi.misaki.donpa.miles.wins.10")
        XCTAssertEqual(
            GameCenterMapping.wireID(.milesWins, tier: 3), "fi.misaki.donpa.miles.wins.1000")
        // A tier on a one-shot falls back to the plain ID (no phantom steps).
        XCTAssertEqual(GameCenterMapping.wireID(.winFirst, tier: 2), "fi.misaki.donpa.win.first")
    }

    func testFreshStateReportsNothing() {
        XCTAssertTrue(GameCenterMapping.snapshot(earned: [:], records: [:]).isEmpty)
    }

    func testOneShotReportsHundred() {
        let reports = GameCenterMapping.snapshot(earned: [.winFirst: 1], records: [:])
        XCTAssertTrue(
            reports.contains(
                GameCenterMapping.Report(wireID: "fi.misaki.donpa.win.first", percent: 100)))
    }

    /// The spec's own example: 470 wins → tiers 10 and 100 earned at 100,
    /// the 1000 step at 47 %.
    func testTierLadderProgress() {
        var record = ScoreRecord()
        record.wins.add(470)
        let records = [GameConfig.beginner.storageKey: record]
        let reports = GameCenterMapping.snapshot(earned: [.milesWins: 2], records: records)
        let byID = Dictionary(uniqueKeysWithValues: reports.map { ($0.wireID, $0.percent) })
        XCTAssertEqual(byID["fi.misaki.donpa.miles.wins.10"], 100)
        XCTAssertEqual(byID["fi.misaki.donpa.miles.wins.100"], 100)
        XCTAssertEqual(byID["fi.misaki.donpa.miles.wins.1000"] ?? 0, 47, accuracy: 0.01)
    }

    /// Progress just short of a threshold never reads as earned (capped 99).
    func testNextTierCapsAtNinetyNine() {
        var record = ScoreRecord()
        record.wins.add(999)
        let records = [GameConfig.beginner.storageKey: record]
        let reports = GameCenterMapping.snapshot(earned: [.milesWins: 2], records: records)
        let last = reports.first { $0.wireID == "fi.misaki.donpa.miles.wins.1000" }
        XCTAssertEqual(last?.percent ?? 0, 99, accuracy: 0.01)
    }

    func testZeroProgressIsOmitted() {
        let reports = GameCenterMapping.snapshot(earned: [:], records: [:])
        XCTAssertFalse(reports.contains { $0.percent == 0 })
    }
}
