import DonpaCore
import XCTest

@testable import DonpaKit

/// The view itself needs UI automation (ignored for coverage), but
/// `MangaPanelView.Kind` is pure logic — the asset name, accent, and spoken
/// label that drive win/loss/record presentation. Lock those down here.
final class MangaPanelKindTests: XCTestCase {
    func testImageName() {
        XCTAssertEqual(MangaPanelView.Kind.win.imageName, "PanelWin")
        XCTAssertEqual(MangaPanelView.Kind.record(centiseconds: 1234).imageName, "PanelWin")
        XCTAssertEqual(
            MangaPanelView.Kind.loss(progress: 0.5, isBest: false).imageName, "PanelLoss")
    }

    func testIsWin() {
        XCTAssertTrue(MangaPanelView.Kind.win.isWin)
        XCTAssertTrue(MangaPanelView.Kind.record(centiseconds: 1).isWin)
        XCTAssertFalse(MangaPanelView.Kind.loss(progress: 0.5, isBest: false).isWin)
    }

    func testBestLossProgress() {
        // Only a new-best loss surfaces a pill value.
        XCTAssertEqual(
            MangaPanelView.Kind.loss(progress: 0.42, isBest: true).bestLossProgress, 0.42)
        XCTAssertNil(MangaPanelView.Kind.loss(progress: 0.42, isBest: false).bestLossProgress)
        XCTAssertNil(MangaPanelView.Kind.win.bestLossProgress)
        XCTAssertNil(MangaPanelView.Kind.record(centiseconds: 1).bestLossProgress)
    }

    func testPercentRounds() {
        XCTAssertEqual(MangaPanelView.Kind.percent(0.0), "0%")
        XCTAssertEqual(MangaPanelView.Kind.percent(0.874), "87%")
        XCTAssertEqual(MangaPanelView.Kind.percent(1.0), "100%")
    }

    func testRecordCentiseconds() {
        XCTAssertEqual(MangaPanelView.Kind.record(centiseconds: 4242).recordCentiseconds, 4242)
        XCTAssertNil(MangaPanelView.Kind.win.recordCentiseconds)
        XCTAssertNil(MangaPanelView.Kind.loss(progress: 0.5, isBest: false).recordCentiseconds)
    }

    func testAccessibilityLabels() {
        XCTAssertEqual(MangaPanelView.Kind.win.a11yLabel, "Minefield cleared")
        XCTAssertTrue(
            MangaPanelView.Kind.loss(progress: 0.5, isBest: false).a11yLabel.contains("Boom"))
        // The record label embeds the formatted time (12.34s = 1234 cs).
        XCTAssertTrue(
            MangaPanelView.Kind.record(centiseconds: 1234).a11yLabel.contains(
                TimeFormat.mmsst(centiseconds: 1234)))
    }
}
