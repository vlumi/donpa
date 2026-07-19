import XCTest

@testable import DonpaCore

/// The nickname facade: trim/cap/clear rules over a mock cloud.
@MainActor
final class DeviceNicknamesTests: XCTestCase {
    private final class MockCloud: CloudDeviceNicknames {
        var isAvailable = true
        var stored: [String: String] = [:]
        func readAll() -> [String: String] { stored }
        func write(_ nickname: String?, for deviceID: String) {
            stored[deviceID] = nickname
        }
    }

    func testTrimsCapsAndClears() {
        let cloud = MockCloud()
        let nicknames = DeviceNicknames(cloud: cloud)
        nicknames.set("  Study Mac  ", for: "a")
        XCTAssertEqual(cloud.stored["a"], "Study Mac")
        XCTAssertEqual(nicknames.all(), ["a": "Study Mac"], "reads back what was set")
        nicknames.set(String(repeating: "x", count: 99), for: "a")
        XCTAssertEqual(cloud.stored["a"]?.count, DeviceNicknames.maxLength)
        nicknames.set("   ", for: "a")
        XCTAssertNil(cloud.stored["a"])
    }

    func testUnavailableCloudReadsEmptyAndDropsWrites() {
        let cloud = MockCloud()
        cloud.isAvailable = false
        cloud.stored = ["a": "hidden"]
        let nicknames = DeviceNicknames(cloud: cloud)
        XCTAssertEqual(nicknames.all(), [:])
        nicknames.set("name", for: "b")
        XCTAssertNil(cloud.stored["b"])
    }
}
