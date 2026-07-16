import XCTest

@testable import DonpaCore

final class TimeFormatTests: XCTestCase {
    func testZero() {
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 0), "0:00.0")
    }

    func testSubMinute() {
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 470), "0:04.7")  // 4.70s
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 9), "0:00.0")  // truncates 0.09→0.0
    }

    func testSecondsPadToTwoDigits() {
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 530), "0:05.3")
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 5900), "0:59.0")
    }

    func testMinutesRollOver() {
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 6000), "1:00.0")  // 60.00s
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 12553), "2:05.5")  // 125.53s → 2:05.5
    }

    func testUncappedLongTimes() {
        // Well past the old 999s cap (1000s = 16:40.0), still under an hour.
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 100_000), "16:40.0")
    }

    /// Past an hour the format rolls into h:mm:ss.t, so a marathon XXXL clear stays
    /// narrow (a 3h game read "180:00.0" before) — and minutes/seconds zero-pad.
    func testRollsIntoHours() {
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 359_990), "59:59.9")  // just under 1h
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 360_000), "1:00:00.0")  // exactly 1h
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 1_080_000), "3:00:00.0")  // 3h
        // 1h 23m 43.5s (502356cs) → hours + zero-padded m:ss.
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 502_356), "1:23:43.5")
        // Tens of hours (a marathon XXXL) still formats — hours aren't capped.
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 8_493_000), "23:35:30.0")
    }

    /// Truncation, never rounding up: the in-game timer truncates to whole seconds,
    /// so a recorded time must not display MORE than the clock ever showed (a timer
    /// reading "49" recording as "50.0" was the bug).
    func testTruncatesToTenth() {
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 474), "0:04.7")  // 4.74 → 4.7
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 475), "0:04.7")  // 4.75 → 4.7
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 479), "0:04.7")  // 4.79 → 4.7
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 4995), "0:49.9")  // 49.95 → 49.9
    }

    /// The "improved by" pill shows the change in the DISPLAYED value, not the raw
    /// centisecond delta — the two disagree when both times truncate to the same tenth.
    func testDisplayedImprovement() {
        // 18.24 → 18.15: raw delta 9cs, but the display went 18.2 → 18.1 = one tenth.
        XCTAssertEqual(TimeFormat.displayedImprovement(from: 1824, to: 1815), 10)
        // 18.24 → 18.21: both display 18.2 — no visible improvement, no pill.
        XCTAssertNil(TimeFormat.displayedImprovement(from: 1824, to: 1821))
        // A regression or tie never yields a pill.
        XCTAssertNil(TimeFormat.displayedImprovement(from: 1815, to: 1824))
        // Multi-tenth improvements pass through: 20.0 → 18.1 displays as 1.9 faster.
        XCTAssertEqual(TimeFormat.displayedImprovement(from: 2000, to: 1810), 190)
    }

    func testDisplayedDelta() {
        // Each side truncates to its tenth BEFORE subtracting, so the result
        // matches the two times on screen. 1.56 and 1.62 both display two
        // tenths apart? No — 1.5 vs 1.6 = one tenth, whatever the hidden cs.
        XCTAssertEqual(TimeFormat.displayedDelta(156, 162), 10)
        XCTAssertEqual(TimeFormat.displayedDelta(162, 156), -10)
        // Same displayed tenth → zero, no phantom sub-tenth diff.
        XCTAssertEqual(TimeFormat.displayedDelta(154, 159), 0)
    }

    func testSignedGap() {
        // Built from the two RAW times, quantized to displayed tenths: 1.5 vs
        // 1.6 reads one tenth even though the raw diff is smaller.
        XCTAssertEqual(TimeFormat.signedGap(mine: 156, theirs: 162), "−0:00.1")
        XCTAssertEqual(TimeFormat.signedGap(mine: 162, theirs: 156), "+0:00.1")
        // Same displayed tenth → nothing (no signed "0.0").
        XCTAssertEqual(TimeFormat.signedGap(mine: 154, theirs: 159), "")
        // A whole-tenth gap keeps its magnitude and sign.
        XCTAssertEqual(TimeFormat.signedGap(mine: 800, theirs: 950), "−0:01.5")
    }
}
