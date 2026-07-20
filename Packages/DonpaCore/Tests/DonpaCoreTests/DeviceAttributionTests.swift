import XCTest

@testable import DonpaCore

/// The Record's attribution index: a glyph only when the owner is unambiguous.
@MainActor
final class DeviceAttributionTests: XCTestCase {
    private let key = GameConfig.beginner.storageKey

    private func table(
        best: Int, at seconds: TimeInterval, top: [Int] = []
    ) -> [String: ScoreRecord] {
        let stamp = Date(timeIntervalSince1970: seconds)
        var record = ScoreRecord()
        record.best = BestTime(centiseconds: best, achievedAt: stamp)
        record.topTimes =
            [record.best!] + top.map { BestTime(centiseconds: $0, achievedAt: stamp) }
        return [key: record]
    }

    func testUniqueOwnerGetsItsClass() {
        let index = DeviceAttribution(
            tables: ["mac": table(best: 200, at: 1), "phone": table(best: 300, at: 2)],
            classes: ["mac": .mac, "phone": .phone])
        XCTAssertEqual(
            index.deviceClass(
                for: BestTime(centiseconds: 200, achievedAt: Date(timeIntervalSince1970: 1)),
                config: key),
            .mac)
        XCTAssertEqual(
            index.deviceClass(
                for: BestTime(centiseconds: 300, achievedAt: Date(timeIntervalSince1970: 2)),
                config: key),
            .phone)
    }

    func testTopTimesAttributeToo() {
        let index = DeviceAttribution(
            tables: ["pad": table(best: 200, at: 1, top: [450]), "mac": table(best: 300, at: 2)],
            classes: ["pad": .pad, "mac": .mac])
        XCTAssertEqual(
            index.deviceClass(
                for: BestTime(centiseconds: 450, achievedAt: Date(timeIntervalSince1970: 1)),
                config: key),
            .pad)
    }

    func testCrossClassTieStaysBlank() {
        let time = BestTime(centiseconds: 200, achievedAt: Date(timeIntervalSince1970: 1))
        let index = DeviceAttribution(
            tables: ["mac": table(best: 200, at: 1), "phone": table(best: 200, at: 1)],
            classes: ["mac": .mac, "phone": .phone])
        XCTAssertNil(index.deviceClass(for: time, config: key))
    }

    func testSameClassTieStillShows() {
        let time = BestTime(centiseconds: 200, achievedAt: Date(timeIntervalSince1970: 1))
        let index = DeviceAttribution(
            tables: ["p1": table(best: 200, at: 1), "p2": table(best: 200, at: 1)],
            classes: ["p1": .phone, "p2": .phone])
        XCTAssertEqual(index.deviceClass(for: time, config: key), .phone)
    }

    func testUnknownBlobStaysBlank() {
        let time = BestTime(centiseconds: 200, achievedAt: Date(timeIntervalSince1970: 1))
        let index = DeviceAttribution(
            tables: ["ghost": table(best: 200, at: 1), "mac": table(best: 300, at: 2)],
            classes: ["mac": .mac])
        XCTAssertNil(index.deviceClass(for: time, config: key))
    }

    func testSingleDeviceHouseholdIsSilent() {
        let time = BestTime(centiseconds: 200, achievedAt: Date(timeIntervalSince1970: 1))
        let index = DeviceAttribution(
            tables: ["mac": table(best: 200, at: 1)], classes: ["mac": .mac])
        XCTAssertNil(index.deviceClass(for: time, config: key))
    }
}
