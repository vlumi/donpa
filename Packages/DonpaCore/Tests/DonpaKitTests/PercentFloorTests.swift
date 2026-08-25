import XCTest

@testable import DonpaKit

/// Cleared-progress percentages floor, never round: a 99.x% non-clear must never
/// read "100%". Locale formatting varies ("99 %" / "99%"), so assert on the digits.
final class PercentFloorTests: XCTestCase {
    private func digits(_ s: String) -> Int {
        Int(s.filter(\.isNumber)) ?? -1
    }

    func testFloorsRatherThanRounds() {
        XCTAssertEqual(digits(StatBlock.percentFloor(0.876)), 87)  // not 88
        XCTAssertEqual(digits(StatBlock.percentFloor(0.036)), 3)  // not 4
    }

    func testNearClearNeverReadsHundred() {
        XCTAssertEqual(digits(StatBlock.percentFloor(0.997)), 99)  // the whole point
        XCTAssertEqual(digits(StatBlock.percentFloor(0.999)), 99)
    }

    func testExactBoundaries() {
        XCTAssertEqual(digits(StatBlock.percentFloor(1.0)), 100)  // a real full clear
        XCTAssertEqual(digits(StatBlock.percentFloor(0.0)), 0)
    }
}
