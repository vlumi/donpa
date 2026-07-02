import DonpaCore
import XCTest

@testable import DonpaKit

/// `Settings.currentConfig` is what the New Game popup turns the player's pending
/// choices into — family + axes. Lock the mapping, persistence, and the one-time
/// migration from the pre-family (mode + shape) keys.
@MainActor
final class SettingsConfigTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    func testDefaultsAreBasicFlat() {
        let settings = Settings(defaults: freshDefaults())
        XCTAssertEqual(settings.family, .basic)
        XCTAssertEqual(settings.gridEdges, .flat, "Round is opt-in")
        XCTAssertEqual(settings.hiveEdges, .flat)
        XCTAssertEqual(settings.currentConfig, .basic(.beginner))
    }

    func testCurrentConfigCarriesTheFamilysOwnAxes() {
        let settings = Settings(defaults: freshDefaults())
        settings.family = .grid
        settings.gridEdges = .round
        XCTAssertEqual(
            settings.currentConfig, .grid(settings.gridSize, settings.gridDensity, .round),
            "the picker's choices flow into the config")
        XCTAssertTrue(settings.currentConfig.topology is WrappedSquareTopology)

        // Basic is always Flat, regardless of any Grid/Hive edges setting.
        settings.family = .basic
        XCTAssertEqual(settings.currentConfig.edges, .flat)
    }

    func testGridAndHiveSelectionsAreIndependent() {
        // Picking a huge Round hive must not retune the next Grid game — each
        // family remembers its own difficulty/size/edges (user decision).
        let settings = Settings(defaults: freshDefaults())
        settings.family = .hive
        settings.hiveSize = .xxl
        settings.hiveDensity = .insane
        settings.hiveEdges = .round
        XCTAssertEqual(settings.currentConfig, .hive(.xxl, .insane, .round))

        settings.family = .grid
        XCTAssertEqual(
            settings.currentConfig, .grid(.s, .normal, .flat),
            "grid keeps its own defaults, untouched by the hive spree")
    }

    func testFamilyAndAxesPersist() {
        let defaults = freshDefaults()
        let first = Settings(defaults: defaults)
        first.family = .hive
        first.hiveEdges = .round
        first.gridSize = .xl
        // A fresh Settings on the same store restores the choices per family.
        let second = Settings(defaults: defaults)
        XCTAssertEqual(second.family, .hive)
        XCTAssertEqual(second.hiveEdges, .round)
        XCTAssertEqual(second.gridSize, .xl)
        XCTAssertEqual(second.gridEdges, .flat, "grid's edges were never touched")
    }

    func testMigratesLegacySharedKeysIntoBothFamilies() {
        // A pre-family install stored mode/shape + ONE shared size/density/edges
        // set in the old vocabulary; a hex-on-wrapped player must come back as
        // Hive + Round, and the old shared picks seed BOTH families' own axes.
        let defaults = freshDefaults()
        defaults.set("modern", forKey: "donpa.mode")
        defaults.set("hex", forKey: "donpa.modernShape")
        defaults.set("wrapped", forKey: "donpa.modernEdges")
        defaults.set("m", forKey: "donpa.modernSize")
        defaults.set("hard", forKey: "donpa.modernDensity")
        let migrated = Settings(defaults: defaults)
        XCTAssertEqual(migrated.family, .hive)
        XCTAssertEqual(migrated.hiveEdges, .round)
        XCTAssertEqual(migrated.hiveSize, .m)
        XCTAssertEqual(migrated.gridDensity, .hard, "the shared pick seeds grid too")
        XCTAssertEqual(migrated.gridEdges, .round)

        // And a classic player lands on Basic.
        let classicDefaults = freshDefaults()
        classicDefaults.set("classic", forKey: "donpa.mode")
        XCTAssertEqual(Settings(defaults: classicDefaults).family, .basic)
    }
}
