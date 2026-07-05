import XCTest

/// Local-only UI regression tests (run via `make uitest`, never on CI). They
/// cover the navigation/sheet flows that regressed repeatedly during UI work:
/// title → New Game popup → board, the Settings/High Scores sheets dismissing,
/// and pause/resume. Queries use accessibility identifiers (stable across
/// locales) set in the app via `.accessibilityIdentifier(...)`.
final class DonpaUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // Clean, isolated state per run: no saved game restored, and the app uses
        // an ephemeral save store — so tests are deterministic and never touch the
        // developer's real save.
        app.launchArguments += ["-uitest-clean"]
        // Force English so any label-based fallbacks are predictable.
        app.launchArguments += ["-AppleLanguages", "(en)"]
        app.launch()
    }

    // MARK: Helpers

    /// The title art ("press start") button.
    private var startButton: XCUIElement { app.buttons["title.start"] }

    private func waitFor(_ element: XCUIElement, _ timeout: TimeInterval = 5) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "missing: \(element)")
    }

    // MARK: Tests

    func testLaunchShowsTitle() {
        waitFor(startButton)
    }

    /// From the title, open the New Game popup and start a game. The in-game
    /// control strip (the Home button) appearing is the reliable "we're playing"
    /// signal — the board is an always-mounted SpriteView that doesn't surface
    /// cleanly as a queryable element.
    private func startGame() {
        waitFor(startButton)
        startButton.tap()
        let popupStart = app.buttons["newgame.start"]
        waitFor(popupStart)
        popupStart.tap()
        waitFor(app.buttons["game.home"])
    }

    func testStartOpensNewGamePopupThenStartsGame() {
        startGame()
        // The title's start button is no longer hittable once playing.
        XCTAssertFalse(startButton.isHittable)
    }

    func testHighScoresSheetOpensAndCloses() {
        waitFor(app.buttons["title.highScores"])
        app.buttons["title.highScores"].tap()
        let done = app.buttons["sheet.done"]
        waitFor(done)
        done.tap()
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), "back on the title")
    }

    func testSettingsSheetOpensAndCloses() {
        waitFor(app.buttons["title.settings"])
        app.buttons["title.settings"].tap()
        let done = app.buttons["sheet.done"]
        waitFor(done)
        done.tap()
        waitFor(startButton)
    }

    func testHomeReturnsToTitleFromGame() {
        startGame()
        app.buttons["game.home"].tap()
        waitFor(startButton)
    }

    /// Going Home from an in-progress game saves it (rather than discarding), and
    /// tapping the title art resumes that game directly — no New Game popup. This
    /// is the save-on-home behaviour; the regression it guards is Home silently
    /// ending the game.
    func testHomeSavesAndTitleResumes() {
        startGame()
        // Make a move so there's a genuine in-progress (playing) game to save.
        XCTAssertTrue(
            app.buttons["newgame.start"].waitForNonExistence(timeout: 5),
            "New Game popup dismissed")
        app.otherElements["game.board"].tap()
        // Go home — should pause + save, not discard.
        app.buttons["game.home"].tap()
        waitFor(startButton)
        // Tapping the title resumes straight into the game (Home button present),
        // and must NOT open the New Game popup (that would mean nothing was saved).
        startButton.tap()
        waitFor(app.buttons["game.home"])
        XCTAssertFalse(
            app.buttons["newgame.start"].exists,
            "resumed directly, no New Game popup")
    }

    /// Regression: start a game, make a move, reopen New Game on the SAME config.
    /// The Start button must read "Continue" (the live game is flushed to disk when
    /// New Game opens, so its in-progress cue is accurate immediately — it used to
    /// show a plain "Start" until the debounced save happened to land). English is
    /// forced in setUp, so the label check is stable.
    func testNewGameShowsContinueForTheLiveGame() {
        startGame()
        XCTAssertTrue(
            app.buttons["newgame.start"].waitForNonExistence(timeout: 5),
            "New Game popup dismissed")
        app.otherElements["game.board"].tap()  // first move → in-progress game
        waitFor(app.buttons["game.pause"])  // confirm we're actually playing
        // Reopen New Game via the in-game config badge (flushes the live game first).
        app.buttons["game.config"].tap()
        let button = app.buttons["newgame.start"]
        waitFor(button)
        XCTAssertEqual(
            button.label, "Continue",
            "the just-played config offers Continue, not a fresh Start")
    }

    /// Home shows a Continue card for the in-progress game (fresh the moment Home
    /// appears — goHome flushes the save inline), and tapping it resumes play.
    func testHomeShowsContinueCardAndResumes() {
        startGame()
        XCTAssertTrue(
            app.buttons["newgame.start"].waitForNonExistence(timeout: 5),
            "New Game popup dismissed")
        app.otherElements["game.board"].tap()  // first move → a real in-progress game
        app.buttons["game.home"].tap()
        let card = app.buttons["home.continue"]
        waitFor(card)
        card.tap()
        waitFor(app.buttons["game.home"])
        XCTAssertFalse(
            app.buttons["newgame.start"].exists, "resumed directly, no New Game popup")
    }

    /// Regression: the New Game popup pauses a live game (browsing configs shouldn't
    /// cost clock time) and resumes on dismiss — the resume is owned by the popup, so
    /// it only fires when the popup did the pausing.
    func testNewGamePopupPausesTheGame() {
        startGame()
        XCTAssertTrue(
            app.buttons["newgame.start"].waitForNonExistence(timeout: 5),
            "New Game popup dismissed")
        app.otherElements["game.board"].tap()  // first move → clock running
        waitFor(app.buttons["game.pause"])
        // Open New Game over the live game — the clock must freeze.
        app.buttons["game.config"].tap()
        waitFor(app.buttons["newgame.start"])
        let paused = app.descendants(matching: .any)["game.paused"]
        waitFor(paused)
        // Dismiss without starting — the game resumes.
        app.buttons["Close"].tap()
        XCTAssertTrue(paused.waitForNonExistence(timeout: 5), "dismiss resumes the game")
    }

    func testPauseAndResume() {
        startGame()
        // Wait for the New Game popup to finish fading out — its dimmed scrim
        // captures taps until then, so tapping the board too early hits the scrim
        // (no first move, no pause). The popup's Start button vanishing is the
        // "popup gone" signal.
        XCTAssertTrue(
            app.buttons["newgame.start"].waitForNonExistence(timeout: 5),
            "New Game popup dismissed")
        // Pause only exists once the game is actually playing, so reveal a cell
        // first (tap the board to make the first move).
        app.otherElements["game.board"].tap()
        let pause = app.buttons["game.pause"]
        waitFor(pause)
        pause.tap()
        // The pause overlay (match by id across any element type).
        let paused = app.descendants(matching: .any)["game.paused"]
        waitFor(paused)
        paused.tap()  // tap-to-resume
        XCTAssertFalse(
            app.descendants(matching: .any)["game.paused"].waitForExistence(timeout: 2),
            "resumed")
    }

    // The fullscreen board overview was replaced by the corner minimap (an SKNode
    // with no accessibility identifier), so it has no UI test — the old
    // testOverviewOpensAndCloses waited on `game.overview`, which no longer exists,
    // and could never pass.
}

/// Reproduction for the "board unresponsive after rapid restarts" report: on an XS
/// board under tap storms + instant Retry, the fresh board sometimes ignored taps
/// for a few seconds (chrome stayed live). Measures time-to-first-reveal after each
/// restart — first-click safety makes "progress leaves 0%" a reliable responded
/// signal. Launch includes `-donpa.inputtrace` so the unified log attributes any
/// dead window to the gate / panel / scene (capture via `log stream` while running).
final class RestartStormUITests: XCTestCase {
    func testXSRestartStormRespondsQuickly() {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += [
            "-uitest-clean", "-AppleLanguages", "(en)",
            "-donpa.family", "grid", "-donpa.grid.size", "xs",
            "-donpa.inputtrace",
        ]
        app.launch()

        // Into a game: title → New Game popup (pre-seeded to XS Grid) → Start.
        let start = app.buttons["title.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        let popupStart = app.buttons["newgame.start"]
        XCTAssertTrue(popupStart.waitForExistence(timeout: 5))
        popupStart.tap()
        XCTAssertTrue(app.buttons["game.home"].waitForExistence(timeout: 5))
        // The popup's scrim eats taps until fully gone.
        XCTAssertTrue(popupStart.waitForNonExistence(timeout: 5))

        let board = app.otherElements["game.board"]
        let retry = app.buttons["game.retry"]
        let progress = app.descendants(matching: .any)["game.progress"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(progress.waitForExistence(timeout: 5))

        func progressValue() -> String { (progress.value as? String) ?? "?" }

        var slow: [String] = []
        var worst: TimeInterval = 0
        for round in 1...20 {
            // Tap storm: rapid reveals scattered over the board. Mine hits, game
            // ends, and result panels mid-storm are all part of the reproduction.
            for _ in 0..<8 {
                let v = CGVector(
                    dx: CGFloat.random(in: 0.15...0.85), dy: CGFloat.random(in: 0.2...0.8))
                board.coordinate(withNormalizedOffset: v).tap()
            }
            retry.tap()
            // Fresh board: keep re-tapping like an impatient player; measure how
            // long until the first reveal lands (always safe → progress > 0%).
            let t0 = Date()
            var responded = false
            while Date().timeIntervalSince(t0) < 8 {
                board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                if progressValue() != "0%" {
                    responded = true
                    break
                }
            }
            let dt = Date().timeIntervalSince(t0)
            worst = max(worst, dt)
            if !responded {
                slow.append("round \(round): NEVER responded (8s cap)")
            } else if dt > 1.5 {
                slow.append("round \(round): \(String(format: "%.2f", dt))s")
            }
        }
        print("STORM RESULT worst=\(String(format: "%.2f", worst))s slow=\(slow)")
        XCTAssertTrue(slow.isEmpty, "unresponsive windows: \(slow.joined(separator: "; "))")
    }
}
