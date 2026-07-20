import XCTest

@testable import DonpaCore

/// The class-filtered career reader: gating, filtering, and merge semantics.
@MainActor
final class DeviceClassCareerTests: XCTestCase {
    private let key = GameConfig.beginner.storageKey

    private func table(wins: Int, best: Int) -> [String: ScoreRecord] {
        var record = ScoreRecord()
        record.wins = DeviceCounter(mine: wins)
        record.best = BestTime(centiseconds: best, achievedAt: Date(timeIntervalSince1970: 0))
        // Real records always carry the best in topTimes (submit maintains
        // both); the merged display-best derives from there.
        record.topTimes = [record.best!]
        return [key: record]
    }

    func testAvailableClassesNeedDataAndAClass() {
        let career = DeviceClassCareer(
            tables: [
                "mac": table(wins: 1, best: 300),
                "phone": table(wins: 2, best: 200),
                "idlePad": [:],  // registered but never played — no segment
                "ghost": table(wins: 4, best: 100),  // pre-registry: no class
            ],
            classes: ["mac": .mac, "phone": .phone, "idlePad": .pad])
        XCTAssertEqual(career.availableClasses, [.phone, .mac])
    }

    func testFilteredViewSumsOnlyTheClass() {
        let career = DeviceClassCareer(
            tables: [
                "mac1": table(wins: 3, best: 300),
                "mac2": table(wins: 5, best: 250),
                "phone": table(wins: 2, best: 200),
            ],
            classes: ["mac1": .mac, "mac2": .mac, "phone": .phone])
        let macView = career.records(for: .mac)
        XCTAssertEqual(macView[key]?.wins.total, 8)
        XCTAssertEqual(macView[key]?.bestCentiseconds, 250, "best within the class")
        let phoneView = career.records(for: .phone)
        XCTAssertEqual(phoneView[key]?.wins.total, 2)
    }

    func testUnfilteredViewIncludesUnclassedBlobs() {
        let career = DeviceClassCareer(
            tables: ["mac": table(wins: 3, best: 300), "ghost": table(wins: 4, best: 100)],
            classes: ["mac": .mac])
        let all = career.records(for: nil)
        XCTAssertEqual(all[key]?.wins.total, 7, "ghost counts in the household total")
        XCTAssertEqual(all[key]?.bestCentiseconds, 100)
        XCTAssertEqual(
            career.records(for: .mac)[key]?.wins.total, 3,
            "but never inside a class filter")
    }
}
