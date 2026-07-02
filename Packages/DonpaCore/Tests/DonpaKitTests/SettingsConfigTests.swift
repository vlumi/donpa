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
        XCTAssertEqual(settings.edges, .flat, "Round is opt-in")
        XCTAssertEqual(settings.currentConfig, .basic(.beginner))
    }

    func testCurrentConfigCarriesTheChosenAxes() {
        let settings = Settings(defaults: freshDefaults())
        settings.family = .grid
        settings.edges = .round
        XCTAssertEqual(
            settings.currentConfig, .grid(settings.boardSize, settings.density, .round),
            "the picker's choices flow into the config")
        XCTAssertTrue(settings.currentConfig.topology is WrappedSquareTopology)

        settings.family = .hive
        XCTAssertTrue(
            settings.currentConfig.topology is WrappedHexTopology,
            "the shared edges choice follows the family switch")

        // Basic is always Flat, regardless of the Grid/Hive edges setting.
        settings.family = .basic
        XCTAssertEqual(settings.currentConfig.edges, .flat)
    }

    func testFamilyAndEdgesPersist() {
        let defaults = freshDefaults()
        let first = Settings(defaults: defaults)
        first.family = .hive
        first.edges = .round
        // A fresh Settings on the same store restores the choices.
        let second = Settings(defaults: defaults)
        XCTAssertEqual(second.family, .hive)
        XCTAssertEqual(second.edges, .round)
    }

    func testMigratesLegacyModeShapeAndEdges() {
        // A pre-family install stored mode/shape/edges in the old vocabulary; a
        // hex-on-wrapped player must come back as Hive + Round, not the defaults.
        let defaults = freshDefaults()
        defaults.set("modern", forKey: "donpa.mode")
        defaults.set("hex", forKey: "donpa.modernShape")
        defaults.set("wrapped", forKey: "donpa.modernEdges")
        let migrated = Settings(defaults: defaults)
        XCTAssertEqual(migrated.family, .hive)
        XCTAssertEqual(migrated.edges, .round)

        // And a classic player lands on Basic.
        let classicDefaults = freshDefaults()
        classicDefaults.set("classic", forKey: "donpa.mode")
        XCTAssertEqual(Settings(defaults: classicDefaults).family, .basic)
    }
}
