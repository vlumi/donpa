import XCTest

@testable import DonpaKit

/// The synced-flag merge rules from the GC spec: asked is monotonic (OR),
/// enabled is last-writer-wins by decision stamp — OR there would let a
/// stale true beat the opt-out, the one direction the design can't afford.
final class GameCenterPrefsTests: XCTestCase {
    @MainActor func testAskedMergesOr() {
        XCTAssertTrue(GameCenterPrefs.mergedAsked(local: true, remote: false))
        XCTAssertTrue(GameCenterPrefs.mergedAsked(local: false, remote: true))
        XCTAssertFalse(GameCenterPrefs.mergedAsked(local: false, remote: false))
    }

    @MainActor func testEnabledIsLastWriterWinsBothDirections() {
        // A newer remote ON wins…
        var merged = GameCenterPrefs.mergedEnabled(
            local: (on: false, at: 100), remote: (on: true, at: 200))
        XCTAssertTrue(merged.on)
        // …and a newer local OFF beats a stale remote ON (the opt-out must
        // be able to win).
        merged = GameCenterPrefs.mergedEnabled(
            local: (on: false, at: 300), remote: (on: true, at: 200))
        XCTAssertFalse(merged.on)
        // Ties keep the local decision.
        merged = GameCenterPrefs.mergedEnabled(
            local: (on: false, at: 200), remote: (on: true, at: 200))
        XCTAssertFalse(merged.on)
    }

    @MainActor func testDecisionsPersistLocally() {
        let suite = "gc-prefs-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let prefs = GameCenterPrefs(defaults: defaults, kvs: nil)
        XCTAssertFalse(prefs.enabled)
        XCTAssertFalse(prefs.asked)

        prefs.setEnabled(true)
        XCTAssertTrue(prefs.asked, "deciding IS being asked")

        let reloaded = GameCenterPrefs(defaults: defaults, kvs: nil)
        XCTAssertTrue(reloaded.enabled)
        XCTAssertTrue(reloaded.asked)
    }
}
