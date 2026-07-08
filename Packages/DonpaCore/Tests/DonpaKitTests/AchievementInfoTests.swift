import DonpaCore
import XCTest

@testable import DonpaKit

/// Every feat must have a user-facing title (the announce line and the future
/// Decorations grid read them; a missing case would fall back to a raw key).
final class AchievementInfoTests: XCTestCase {
    func testEveryAchievementHasATitle() {
        for id in AchievementID.allCases {
            XCTAssertFalse(id.title.isEmpty, "\(id.rawValue) needs a title")
            XCTAssertFalse(id.title.contains("."), "\(id.rawValue) title looks like a raw key")
        }
    }
}
