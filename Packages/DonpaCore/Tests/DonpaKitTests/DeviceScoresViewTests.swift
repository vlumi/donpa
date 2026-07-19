import XCTest

@testable import DonpaCore
@testable import DonpaKit

/// The row assembly behind "Scores by device": naming, ordering, and the
/// honesty rules (unknown blobs still show; registry-only devices show too).
@MainActor
final class DeviceScoresViewTests: XCTestCase {
    private func info(
        _ id: String, name: String = "Device", active: TimeInterval
    ) -> DeviceInfo {
        DeviceInfo(
            id: id, name: name, model: "Mac1,1", deviceClass: .mac,
            firstSeen: Date(timeIntervalSince1970: 0),
            lastActive: Date(timeIntervalSince1970: active))
    }

    private func table(wins: Int) -> [String: ScoreRecord] {
        var record = ScoreRecord()
        record.wins = DeviceCounter(mine: wins)
        return ["k": record]
    }

    func testThisDeviceLeadsThenNewestActiveThenGhosts() {
        let rows = DeviceScoresView.assemble(
            tables: [
                "me": table(wins: 1), "old": table(wins: 2), "new": table(wins: 3),
                "ghost": table(wins: 4),
            ],
            known: [info("new", active: 200), info("old", active: 100), info("me", active: 300)],
            ownID: "me")
        XCTAssertEqual(rows.map(\.id), ["me", "new", "old", "ghost"])
        XCTAssertTrue(rows[0].isThisDevice)
        XCTAssertNil(rows[3].info)  // the ghost blob has no registry identity
    }

    func testRegistryOnlyDeviceShowsWithZeroSummary() {
        let rows = DeviceScoresView.assemble(
            tables: ["me": table(wins: 1)],
            known: [info("fresh", active: 100)],
            ownID: "me")
        XCTAssertEqual(rows.map(\.id), ["me", "fresh"])
        XCTAssertEqual(rows[1].summary.gamesPlayed, 0)
    }
}
