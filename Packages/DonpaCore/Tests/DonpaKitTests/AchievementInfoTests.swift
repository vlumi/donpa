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

    func testEveryAchievementHasADescription() {
        for id in AchievementID.allCases {
            XCTAssertFalse(id.featDescription.isEmpty, "\(id.rawValue) needs a description")
        }
    }

    /// Descriptions must speak the SHIPPED tier vocabulary — the spec's early
    /// drafts said "Insane", whose in-app label is Legend.
    func testDescriptionsUseShippedTierNames() {
        for id in AchievementID.allCases {
            XCTAssertFalse(
                id.featDescription.contains("Insane"),
                "\(id.rawValue): 'Insane' is not a shipped tier name")
        }
    }
}
