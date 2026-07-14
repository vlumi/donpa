import XCTest

@testable import DonpaKit

final class ReviewPromptTests: XCTestCase {
    func testAsksOnlyForInvestedRecordSettersOncePerVersion() {
        XCTAssertTrue(
            ReviewPrompt.shouldAsk(
                newBest: true, totalWins: 10, promptedVersion: "0.5.0", version: "0.6.0"))
        // Not a best / not invested / already asked this version / no version.
        XCTAssertFalse(
            ReviewPrompt.shouldAsk(
                newBest: false, totalWins: 99, promptedVersion: "", version: "0.6.0"))
        XCTAssertFalse(
            ReviewPrompt.shouldAsk(
                newBest: true, totalWins: 9, promptedVersion: "", version: "0.6.0"))
        XCTAssertFalse(
            ReviewPrompt.shouldAsk(
                newBest: true, totalWins: 10, promptedVersion: "0.6.0", version: "0.6.0"))
        XCTAssertFalse(
            ReviewPrompt.shouldAsk(
                newBest: true, totalWins: 10, promptedVersion: "", version: ""))
    }
}
