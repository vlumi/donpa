import XCTest

@testable import DonpaCore

/// The screenshot/UI-test harness's storage isolation — the pieces that keep
/// seeded demo data away from a real player's records.
final class UITestIsolationTests: XCTestCase {
    func testUITestEphemeralDefaultsIsNotStandardAndRoundTrips() {
        let suite = UserDefaults.uitestEphemeral
        XCTAssertFalse(suite === UserDefaults.standard)
        let key = "isolation-test-\(UUID().uuidString)"
        suite.set("value", forKey: key)
        XCTAssertEqual(suite.string(forKey: key), "value")
        // Never visible through the real defaults.
        XCTAssertNil(UserDefaults.standard.string(forKey: key))
        suite.removeObject(forKey: key)
    }

    func testDemoFixedStoreIsStableAcrossInstances() {
        // Two constructions must see the SAME directory — the demo scripts
        // stage boards into it before launch and freeze them out after quit.
        let writer = SaveStore.demoFixed()
        defer { writer.clear(config: .beginner) }
        var rng = SeededGenerator(seed: 635)
        var game = Game(config: .beginner)
        game.placeMinesEagerly(using: &rng)
        game.reveal(Coord(4, 4), using: &rng)
        guard
            let snapshot = GameSnapshot(
                game: game, config: .beginner, elapsedCentiseconds: 100)
        else { return XCTFail("seed 635 must yield an in-progress game") }
        writer.save(snapshot)
        let reader = SaveStore.demoFixed()
        XCTAssertNotNil(reader.load(config: .beginner))
    }
}
