#if os(macOS)
import XCTest

@testable import DonpaKit

/// The mouse-up click-vs-pan reclassification: a press that crossed the live-pan
/// drag threshold still counts as a CLICK when it was brief and its net travel
/// stayed within the slop — a Magic Mouse slides a few points under its own click
/// force, and without this every rapid click was eaten as an invisible micro-pan.
final class SloppyClickTests: XCTestCase {
    func testBriefSmallDragIsAClick() {
        // The Magic Mouse case: a quick click that slid a little.
        XCTAssertTrue(BoardScene.sloppyClickCountsAsClick(net: 5, duration: 0.10))
        XCTAssertTrue(BoardScene.sloppyClickCountsAsClick(net: 8, duration: 0.3))  // at bounds
    }

    func testLongPressStaysAPan() {
        // Held past the duration cap: a deliberate small adjustment pan.
        XCTAssertFalse(BoardScene.sloppyClickCountsAsClick(net: 5, duration: 0.5))
    }

    func testFarTravelStaysAPan() {
        // A quick flick that genuinely moved: a pan, however brief.
        XCTAssertFalse(BoardScene.sloppyClickCountsAsClick(net: 30, duration: 0.1))
    }

    func testJustPastEitherBoundStaysAPan() {
        XCTAssertFalse(BoardScene.sloppyClickCountsAsClick(net: 8.1, duration: 0.3))
        XCTAssertFalse(BoardScene.sloppyClickCountsAsClick(net: 8, duration: 0.31))
    }
}
#endif
