import XCTest

/// Local-only gating checks (run via `make uitest`, never on CI): under the
/// `-donpa.gates.fresh` launch flag every veteran record is baselined away, so
/// the New Game popup must show the fresh-install teaser state.
final class GatingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uitest-clean", "-donpa.gates.fresh"]
        app.launchArguments += ["-AppleLanguages", "(en)"]
        app.launch()
    }

    /// The fresh ladder in the popup: a locked size chip carries the padlock's
    /// spoken value, and the open starting sizes don't.
    func testFreshGatesLockTheLadder() {
        let start = app.buttons["title.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        let popupStart = app.buttons["newgame.start"]
        XCTAssertTrue(popupStart.waitForExistence(timeout: 5))

        // Size chips expose "SIZE — side×side" labels; the locked ones carry a
        // "Locked — …" accessibility value (LockValue).
        let lockedXL = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'XL' AND value CONTAINS 'Locked'")
        ).firstMatch
        XCTAssertTrue(lockedXL.waitForExistence(timeout: 5), "XL should be locked when fresh")
        let openM = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'M —' AND NOT (value CONTAINS 'Locked')")
        ).firstMatch
        XCTAssertTrue(openM.exists, "M is part of the fresh starting matrix")
    }
}
