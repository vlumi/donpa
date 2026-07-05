import XCTest

@testable import DonpaCore

/// Pure comparison: mixed leaderboard ranking (you interleaved among rivals by time),
/// your N/M position, and head-to-head tallies.
final class ScoreComparisonTests: XCTestCase {
    func testMixedLeaderboardInterleavesYouByTime() {
        let r = ScoreComparison.rank(
            yourName: "You", yourBest: 940,
            rivals: [("Amy", 810), ("Bob", 1170)])
        // Fastest first: Amy 8.1, You 9.4, Bob 11.7 — you slotted in, not appended.
        XCTAssertEqual(r.entries.map(\.name), ["Amy", "You", "Bob"])
        XCTAssertEqual(r.yourRank, 2)
        XCTAssertEqual(r.rankedCount, 3)
        XCTAssertTrue(r.entries[1].isYou)
    }

    func testUnwonTimesSinkAndDontRank() {
        let r = ScoreComparison.rank(
            yourName: "You", yourBest: nil,
            rivals: [("Amy", 810), ("Bob", nil)])
        // Winners first (Amy), then the unwon in name order (Bob, You).
        XCTAssertEqual(r.entries.map(\.name), ["Amy", "Bob", "You"])
        XCTAssertNil(r.yourRank)  // you haven't won → no rank
        XCTAssertEqual(r.rankedCount, 1)  // only Amy has a time
    }

    func testTiesBreakByNameDeterministically() {
        let r = ScoreComparison.rank(
            yourName: "You", yourBest: 500, rivals: [("Amy", 500)])
        XCTAssertEqual(r.entries.map(\.name), ["Amy", "You"])  // equal time → name order
        XCTAssertEqual(r.yourRank, 2)
    }

    func testYourEntryLocatableWhenOutsideTopFive() throws {
        // Six rivals all faster than you → you rank 7th; the UI shows top-5 then your
        // row below. Assert the data supports that: your rank + a findable entry.
        let rivals = (1...6).map { (name: "R\($0)", best: 100 + $0 * 10) }
        let r = ScoreComparison.rank(yourName: "You", yourBest: 1000, rivals: rivals)
        XCTAssertEqual(r.yourRank, 7)
        XCTAssertEqual(r.rankedCount, 7)
        let you = try XCTUnwrap(r.entries.first { $0.isYou })
        XCTAssertEqual(you.best, 1000)
        XCTAssertGreaterThan(r.yourRank ?? 0, 5)  // UI appends below the top-5 with a break
    }

    func testHeadToHeadTally() {
        let keys = ["a", "b", "c", "d"]
        // Absent key = unwon (no nil values needed).
        let h = ScoreComparison.headToHead(
            configKeys: keys,
            yourBests: ["a": 100, "b": 500],
            theirBests: ["a": 200, "b": 400, "c": 300])
        // a: you faster; b: they faster; c: only they; d: neither → skipped.
        XCTAssertEqual(h.rows.map(\.configKey), ["a", "b", "c"])
        XCTAssertEqual(h.youLead, 1)
        XCTAssertEqual(h.theyLead, 2)  // b + c (c is theirs-only)
        XCTAssertEqual(h.rows[0].lead, .you)
        XCTAssertEqual(h.rows[2].lead, .them)
    }

    func testGroupBestsTakesFastestMemberAndNamesHolder() {
        let group = ScoreComparison.groupBests([
            (name: "Amy", scores: ["a": 500]),
            (name: "Bob", scores: ["a": 300, "b": 900]),
            (name: "Cid", scores: [:]),
        ])
        XCTAssertEqual(group.times["a"], 300)  // fastest across members
        XCTAssertEqual(group.times["b"], 900)
        XCTAssertEqual(group.holders["a"], "Bob")  // Bob holds board a's best
        XCTAssertEqual(group.holders["b"], "Bob")
    }

    func testHeadToHeadGapAndHolder() {
        let group = ScoreComparison.groupBests([(name: "Amy", scores: ["a": 800])])
        let h = ScoreComparison.headToHead(
            configKeys: ["a"], yourBests: ["a": 940],
            theirBests: group.times, theirHolders: group.holders)
        XCTAssertEqual(h.rows[0].gap, 140)  // you 9.40 vs 8.00 → +1.40s slower
        XCTAssertEqual(h.rows[0].holderName, "Amy")
        XCTAssertEqual(h.rows[0].lead, .them)
    }
}
