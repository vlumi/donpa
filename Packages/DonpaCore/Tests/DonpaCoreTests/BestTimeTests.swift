import XCTest

@testable import DonpaCore

/// The device-owned top-times list and its cross-device merge — the projection the
/// scoreboard's top-N display is built from.
final class BestTimeTests: XCTestCase {
    private func time(_ cs: Int, at seconds: TimeInterval) -> BestTime {
        BestTime(centiseconds: cs, achievedAt: Date(timeIntervalSince1970: seconds))
    }

    func testInsertTopKeepsSortedAndCapped() {
        var top: [BestTime] = []
        XCTAssertTrue(top.insertTop(time(300, at: 1), limit: 3))
        XCTAssertTrue(top.insertTop(time(100, at: 2), limit: 3))
        XCTAssertTrue(top.insertTop(time(200, at: 3), limit: 3))
        XCTAssertEqual(top.map(\.centiseconds), [100, 200, 300], "fastest first")

        // Too slow for a full list: rejected, list unchanged.
        XCTAssertFalse(top.insertTop(time(400, at: 4), limit: 3))
        XCTAssertEqual(top.map(\.centiseconds), [100, 200, 300])

        // Fast enough: inserted in order, slowest entry falls off.
        XCTAssertTrue(top.insertTop(time(150, at: 5), limit: 3))
        XCTAssertEqual(top.map(\.centiseconds), [100, 150, 200])
    }

    func testMergedTopInterleavesDevicesFastestFirst() {
        let mine = [time(120, at: 1), time(300, at: 2)]
        let other = [time(90, at: 3), time(200, at: 4)]
        let merged = mine.mergedTop(with: [other], limit: 3)
        XCTAssertEqual(merged.map(\.centiseconds), [90, 120, 200], "capped cross-device top")
    }

    func testMergedTopDropsDuplicateEntriesButKeepsEqualTimes() {
        // The same clear appearing in overlapping lists must count once…
        let shared = time(100, at: 42)
        let merged = [shared, time(250, at: 1)].mergedTop(with: [[shared]], limit: 10)
        XCTAssertEqual(merged.count, 2, "identical (time, date) entries collapse")
        // …but two DIFFERENT clears with the same time are both real results.
        let tie = [time(100, at: 1)].mergedTop(with: [[time(100, at: 2)]], limit: 10)
        XCTAssertEqual(tie.count, 2, "equal times from distinct clears both survive")
    }
}

/// The per-install identity blobs are keyed by. It must never change once minted —
/// a drifting id would fork a device's cloud history.
final class DeviceIDTests: XCTestCase {
    func testStablePerInstallAndDistinctAcrossInstalls() {
        let suiteA = "deviceid-a-\(UUID().uuidString)"
        let suiteB = "deviceid-b-\(UUID().uuidString)"
        let a = UserDefaults(suiteName: suiteA)!
        let b = UserDefaults(suiteName: suiteB)!
        defer {
            a.removePersistentDomain(forName: suiteA)
            b.removePersistentDomain(forName: suiteB)
        }
        let minted = DeviceID.current(in: a)
        XCTAssertFalse(minted.isEmpty)
        XCTAssertEqual(DeviceID.current(in: a), minted, "repeat reads return the minted id")
        XCTAssertEqual(
            a.string(forKey: DeviceID.defaultsKey), minted,
            "persisted, so it survives relaunch")
        XCTAssertNotEqual(DeviceID.current(in: b), minted, "a separate install mints its own")
    }
}
