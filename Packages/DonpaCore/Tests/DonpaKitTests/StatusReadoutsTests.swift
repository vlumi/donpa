import XCTest

@testable import DonpaKit

/// The HUD timer formatter's three regimes and their boundaries — the last one
/// (rolling into hours) is where a marathon board used to freeze at 99:59.
final class StatusReadoutsTests: XCTestCase {
    private func time(_ centiseconds: Int) -> String {
        CounterReadout.time(centiseconds: centiseconds, tint: .primary).value
    }

    func testUnderThousandSecondsIsZeroPadded() {
        XCTAssertEqual(time(0), "000")
        XCTAssertEqual(time(4_700), "047")
        XCTAssertEqual(time(999_00), "999")
    }

    func testRollsToMinutesAtAThousandSeconds() {
        XCTAssertEqual(time(1_000_00), "16:40")
    }

    func testRollsToHoursPastFiftyNineFiftyNine() {
        // The old cap stuck here at 99:59; now it keeps counting.
        XCTAssertEqual(time(3_599_00), "59:59")
        XCTAssertEqual(time(3_600_00), "1:00:00")
        XCTAssertEqual(time(6_023_00), "1:40:23")  // past the old 99:59 ceiling
    }

    func testNegativeClampsToZero() {
        XCTAssertEqual(time(-500), "000")
    }
}
