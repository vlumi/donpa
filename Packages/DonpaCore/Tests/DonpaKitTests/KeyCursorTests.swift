import XCTest

@testable import DonpaKit

/// The keyboard-navigation math every zoned surface rides on. These encode
/// the settled vocabulary: Tab wraps through VISIBLE zones (first Tab enters
/// at the start, Shift-Tab at the end), entering a list seeds its item
/// focus, arrows clamp within a zone.
final class KeyCursorTests: XCTestCase {
    private enum Zone: CaseIterable { case name, list, footer }

    // MARK: cycle

    func testFirstTabEntersAtStart() {
        var cursor = KeyCursor<Zone>()
        cursor.cycle(1, through: Zone.allCases)
        XCTAssertEqual(cursor.zone, .name)
    }

    func testFirstShiftTabEntersAtEnd() {
        var cursor = KeyCursor<Zone>()
        cursor.cycle(-1, through: Zone.allCases)
        XCTAssertEqual(cursor.zone, .footer)
    }

    func testTabWrapsForwardPastTheEnd() {
        var cursor = KeyCursor<Zone>()
        cursor.enter(.footer)
        cursor.cycle(1, through: Zone.allCases)
        XCTAssertEqual(cursor.zone, .name)
    }

    func testShiftTabWrapsBackwardPastTheStart() {
        var cursor = KeyCursor<Zone>()
        cursor.enter(.name)
        cursor.cycle(-1, through: Zone.allCases)
        XCTAssertEqual(cursor.zone, .footer)
    }

    func testHiddenZoneIsSkipped() {
        var cursor = KeyCursor<Zone>()
        cursor.enter(.name)
        cursor.cycle(1, through: [.name, .footer])  // .list hidden
        XCTAssertEqual(cursor.zone, .footer)
    }

    /// The current zone disappearing (filter change) restarts the ring
    /// rather than crashing or sticking.
    func testCycleFromAVanishedZoneReenters() {
        var cursor = KeyCursor<Zone>()
        cursor.enter(.list)
        cursor.cycle(1, through: [.name, .footer])
        XCTAssertEqual(cursor.zone, .name)
    }

    func testNoVisibleZonesClearsTheCursor() {
        var cursor = KeyCursor<Zone>()
        cursor.enter(.list)
        cursor.index = 2
        XCTAssertNil(cursor.cycle(1, through: []))
        XCTAssertNil(cursor.zone)
        XCTAssertNil(cursor.index)
    }

    // MARK: enter + seeding

    func testEnteringAListSeedsItsItemFocus() {
        var cursor = KeyCursor<Zone>()
        let entry = cursor.enter(.list) { _ in .list(seed: 3) }
        XCTAssertEqual(entry, .list(seed: 3))
        XCTAssertEqual(cursor.index, 3)
    }

    func testReenteringAListKeepsAnExistingIndex() {
        var cursor = KeyCursor<Zone>()
        cursor.enter(.list) { _ in .list(seed: 0) }
        cursor.move(2, count: 5)
        cursor.enter(.list) { _ in .list(seed: 0) }
        XCTAssertEqual(cursor.index, 2)
    }

    func testChangingZonesDropsTheOldItemFocus() {
        var cursor = KeyCursor<Zone>()
        cursor.enter(.list) { _ in .list(seed: 4) }
        cursor.enter(.name)
        XCTAssertNil(cursor.index)
    }

    func testFieldEntryReportsField() {
        var cursor = KeyCursor<Zone>()
        XCTAssertEqual(cursor.enter(.name) { _ in .field }, .field)
        XCTAssertNil(cursor.index)
    }

    // MARK: move (in-zone arrows)

    func testMoveClampsAtBothEnds() {
        var cursor = KeyCursor<Zone>()
        cursor.enter(.list) { _ in .list(seed: 0) }
        cursor.move(-1, count: 3)
        XCTAssertEqual(cursor.index, 0)
        cursor.move(5, count: 3)
        XCTAssertEqual(cursor.index, 2)
    }

    func testMoveSeedsAtZeroOnFirstPress() {
        var cursor = KeyCursor<Zone>()
        cursor.enter(.list)
        cursor.move(1, count: 3)
        XCTAssertEqual(cursor.index, 0)
    }

    func testMoveOnAnEmptyListClearsTheIndex() {
        var cursor = KeyCursor<Zone>()
        cursor.enter(.list) { _ in .list(seed: 0) }
        cursor.move(1, count: 0)
        XCTAssertNil(cursor.index)
    }

    /// The list shrank under the focus (a peer left, a row was deleted):
    /// the next step lands inside the new bounds.
    func testMoveClampsAfterTheListShrank() {
        var cursor = KeyCursor<Zone>()
        cursor.enter(.list) { _ in .list(seed: 0) }
        cursor.move(4, count: 5)
        XCTAssertEqual(cursor.index, 4)
        cursor.move(1, count: 2)
        XCTAssertEqual(cursor.index, 1)
    }

    // MARK: KeyStep

    func testKeyStepClampsAlongTheLadder() {
        XCTAssertEqual(KeyStep.clamped(2, by: 1, within: [1, 2, 3]), 3)
        XCTAssertEqual(KeyStep.clamped(3, by: 1, within: [1, 2, 3]), 3)
        XCTAssertEqual(KeyStep.clamped(1, by: -1, within: [1, 2, 3]), 1)
        // Off-ladder (a gated/locked value): step INTO the ladder, not stay invalid.
        XCTAssertEqual(KeyStep.clamped(9, by: 1, within: [1, 2, 3]), 1)
        XCTAssertEqual(KeyStep.clamped(9, by: 1, within: [Int]()), 9)
    }

    func testKeyStepMovedSeedsClampsAndClears() {
        XCTAssertEqual(KeyStep.moved(nil, by: 1, count: 3), 0)
        XCTAssertEqual(KeyStep.moved(nil, by: -1, count: 3), 0)
        XCTAssertEqual(KeyStep.moved(1, by: 1, count: 3), 2)
        XCTAssertEqual(KeyStep.moved(2, by: 1, count: 3), 2)
        XCTAssertEqual(KeyStep.moved(0, by: -1, count: 3), 0)
        XCTAssertNil(KeyStep.moved(1, by: 1, count: 0))
    }

    // MARK: Pulse

    func testPulseFiresMonotonicallyAndComparesByCount() {
        var pulse = Pulse()
        let idle = pulse
        pulse.fire()
        XCTAssertNotEqual(pulse, idle)
        XCTAssertEqual(pulse.count, 1)
        pulse.fire()
        XCTAssertEqual(pulse.count, 2)
    }
}
