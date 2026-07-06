import XCTest

@testable import DonpaCore

final class FullClearTests: XCTestCase {
    func testCompleteGroupSums() {
        let s = FullClear.standing(bests: [100, 200, 300])
        XCTAssertEqual(s.cleared, 3)
        XCTAssertEqual(s.total, 3)
        XCTAssertEqual(s.sumCentiseconds, 600)
    }

    /// A hole in the group means no sum — a partial sum would reward playing less.
    func testPartialGroupHasNoSum() {
        let s = FullClear.standing(bests: [100, nil, 300])
        XCTAssertEqual(s.cleared, 2)
        XCTAssertEqual(s.total, 3)
        XCTAssertNil(s.sumCentiseconds)
    }

    func testUntouchedGroup() {
        let s = FullClear.standing(bests: [nil, nil])
        XCTAssertEqual(s.cleared, 0)
        XCTAssertNil(s.sumCentiseconds)
    }

    func testEmptyGroupNeverSums() {
        XCTAssertNil(FullClear.standing(bests: []).sumCentiseconds)
    }
}
