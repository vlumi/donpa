import DonpaCore
import XCTest

@testable import DonpaKit

@MainActor
final class SettingsTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let suite = "settings-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testFreshInstallDefaults() {
        let settings = Settings(defaults: freshDefaults())
        XCTAssertEqual(settings.family, .practice)  // the no-guess on-ramp
        XCTAssertEqual(settings.gridSize, .s)
        XCTAssertTrue(settings.sound)
        XCTAssertTrue(settings.showMinimap)
        XCTAssertFalse(settings.syncScores)
        XCTAssertFalse(settings.unlockAll)
    }

    func testStoredValuesRoundTripAcrossInstances() {
        let defaults = freshDefaults()
        let settings = Settings(defaults: defaults)
        settings.family = .hive
        settings.hiveSize = .xl
        settings.sound = false
        settings.scoreFilterFamily = .grid

        let reloaded = Settings(defaults: defaults)
        XCTAssertEqual(reloaded.family, .hive)
        XCTAssertEqual(reloaded.hiveSize, .xl)
        XCTAssertFalse(reloaded.sound)
        XCTAssertEqual(reloaded.scoreFilterFamily, .grid)
    }

    func testLegacyModeShapeMigratesToFamilyAndSeedsBothAxes() {
        let defaults = freshDefaults()
        defaults.set("modern", forKey: "donpa.mode")
        defaults.set("hex", forKey: "donpa.modernShape")
        defaults.set("l", forKey: "donpa.modernSize")
        defaults.set("wrapped", forKey: "donpa.modernEdges")

        let settings = Settings(defaults: defaults)
        XCTAssertEqual(settings.family, .hive)
        // The shared legacy axes seed BOTH families; edges translate vocabulary.
        XCTAssertEqual(settings.gridSize, .l)
        XCTAssertEqual(settings.hiveSize, .l)
        XCTAssertEqual(settings.gridEdges, .round)
        XCTAssertEqual(settings.hiveEdges, .round)
    }

    func testLegacyClassicModeMigratesToBasicNotDrills() {
        let defaults = freshDefaults()
        defaults.set("classic", forKey: "donpa.mode")
        let settings = Settings(defaults: defaults)
        XCTAssertEqual(settings.family, .basic)
    }

    func testOwnEdgesKeyInLegacyVocabularyIsTranslated() {
        let defaults = freshDefaults()
        defaults.set("bounded", forKey: "donpa.grid.edges")
        let settings = Settings(defaults: defaults)
        XCTAssertEqual(settings.gridEdges, .flat)
    }

    func testOffLadderPracticeSizeIsDropped() {
        let defaults = freshDefaults()
        defaults.set("xxxl", forKey: "donpa.practice.size")
        let settings = Settings(defaults: defaults)
        XCTAssertEqual(settings.practiceSize, .s)
    }

    /// Migration must not overwrite a family key a newer build already wrote.
    func testMigrationNeverClobbersExistingKeys() {
        let defaults = freshDefaults()
        defaults.set("modern", forKey: "donpa.mode")
        defaults.set("basic", forKey: "donpa.family")
        defaults.set("m", forKey: "donpa.grid.size")
        defaults.set("l", forKey: "donpa.modernSize")

        let settings = Settings(defaults: defaults)
        XCTAssertEqual(settings.family, .basic)
        XCTAssertEqual(settings.gridSize, .m)
    }
}
