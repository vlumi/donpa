import XCTest

/// Local-only screenshot capture for the website gallery and the App Store
/// listing. NOT part of CI and not a regression test — it drives the app to
/// each showcase screen and saves a full-screen screenshot as a test
/// attachment. `Scripts/screenshots.sh` runs this and extracts the PNGs from
/// the .xcresult by name. Run: `make screenshots`.
///
/// Deterministic state via `-uitest-clean` (ephemeral store) plus a seeded
/// demo profile (`-uitest-demo`) so the board, scores, and rivals look
/// populated rather than empty. English forced for stable, legible captures.
final class ScreenshotCapture: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uitest-clean", "-uitest-demo"]
        app.launchArguments += ["-AppleLanguages", "(en)"]
        app.launch()
    }

    private func waitFor(_ element: XCUIElement, _ timeout: TimeInterval = 8) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "missing: \(element)")
    }

    /// Grab a full-screen shot and attach it under `name` — the extractor
    /// script keys on this name, so it maps 1:1 to `/static/img/shots/<name>.png`.
    private func shoot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// One pass through the app, one screenshot per showcase screen. A single
    /// test keeps the launch/state cost down and the ordering explicit.
    func testCaptureGallery() {
        let start = app.buttons["title.start"]
        waitFor(start)
        shoot("home")

        // New Game picker.
        start.tap()
        let newGameStart = app.buttons["newgame.start"]
        waitFor(newGameStart)
        shoot("newgame")

        // A game in progress (the demo profile seeds an opened board).
        newGameStart.tap()
        waitFor(app.buttons["game.home"])
        shoot("game")

        // Back home, then the Service Record.
        app.buttons["game.home"].tap()
        let scores = app.buttons["title.highScores"]
        waitFor(scores)
        scores.tap()
        waitFor(app.otherElements["scoreboard.play"].firstMatch, 4)
        shoot("scoreboard")
        if app.buttons["sheet.done"].exists { app.buttons["sheet.done"].tap() }

        // The daily challenge (its review overlay is the recognizable screen).
        let daily = app.buttons["home.daily"]
        if daily.waitForExistence(timeout: 4) {
            daily.tap()
            _ = app.buttons["daily.start"].waitForExistence(timeout: 4)
            shoot("daily")
            if app.buttons["sheet.done"].exists { app.buttons["sheet.done"].tap() }
        }

        // The Mess hall (share card + rivals).
        let messHall = app.buttons["title.messHall"]
        if messHall.waitForExistence(timeout: 4) {
            messHall.tap()
            _ = app.buttons["sheet.done"].waitForExistence(timeout: 4)
            shoot("messhall")
        }
    }
}
