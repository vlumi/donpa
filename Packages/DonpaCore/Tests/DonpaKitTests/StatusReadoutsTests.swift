import XCTest

@testable import DonpaKit

/// The HUD timer formatter's three regimes and their two rollovers — each
/// format fills its width (999, then 99:59) before the next takes over.
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

    func testMinutesRunToFullWidthBeforeHours() {
        // m:ss runs all the way to 99:59 before rolling — the same "fill the
        // format first" rule as 999→16:40. Past the hour it stays m:ss (1:00:00
        // would be 60:00 here), so 59:59 → 60:00 → … → 99:59 → 1:40:00.
        XCTAssertEqual(time(3_600_00), "60:00")  // one hour, still m:ss
        XCTAssertEqual(time(5_999_00), "99:59")  // last m:ss value
        XCTAssertEqual(time(6_000_00), "1:40:00")  // rolls to h:mm:ss
        XCTAssertEqual(time(6_023_00), "1:40:23")
    }

    func testNegativeClampsToZero() {
        XCTAssertEqual(time(-500), "000")
    }
}
