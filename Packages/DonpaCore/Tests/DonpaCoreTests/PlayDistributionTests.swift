import XCTest

@testable import DonpaCore

final class PlayDistributionTests: XCTestCase {
    private func entry(
        _ config: GameConfig, games: Int = 0, playtime: Int = 0
    ) -> PlayDistribution.Entry {
        .init(config: config, games: games, playtimeCentiseconds: playtime)
    }

    func testFamilySharesByPlaytime() {
        let entries = [
            entry(.basic(.beginner), playtime: 1000),
            entry(.grid(.m, .normal, .flat), playtime: 2000),
            entry(.hive(.s, .hard, .round), playtime: 1000),
        ]
        let shares = PlayDistribution.shares(entries: entries, metric: .playtime, axis: .family)
        XCTAssertEqual(shares.count, 3)
        XCTAssertEqual(shares[1].fraction, 0.5, accuracy: 0.0001)  // Grid, canonical order
        // Fractions of the axis total sum to 1.
        XCTAssertEqual(shares.reduce(0) { $0 + $1.fraction }, 1.0, accuracy: 0.0001)
    }

    /// Games and playtime are independent pictures of the same entries.
    func testMetricsDiffer() {
        let entries = [
            entry(.grid(.xs, .easy, .flat), games: 30, playtime: 100),  // many quick games
            entry(.grid(.xxxl, .easy, .flat), games: 1, playtime: 9900),  // one marathon
        ]
        let byGames = PlayDistribution.shares(entries: entries, metric: .games, axis: .size)
        let byTime = PlayDistribution.shares(entries: entries, metric: .playtime, axis: .size)
        XCTAssertGreaterThan(byGames.first!.fraction, 0.9)  // XS dominates count
        XCTAssertLessThan(byTime.first!.fraction, 0.1)  // but not time
    }

    /// Basic has no size/density tier, so those axes skip it — the size shares
    /// describe the configurable families only, still summing to 1.
    func testSizeAxisSkipsBasic() {
        let entries = [
            entry(.basic(.expert), playtime: 5000),
            entry(.grid(.m, .normal, .flat), playtime: 1000),
        ]
        let shares = PlayDistribution.shares(entries: entries, metric: .playtime, axis: .size)
        XCTAssertEqual(shares.count, 1)
        XCTAssertEqual(shares.first?.fraction ?? 0, 1.0, accuracy: 0.0001)
    }

    func testZeroSegmentsDropAndEmptyWhenUnplayed() {
        let entries = [entry(.grid(.m, .normal, .flat))]  // zero games, zero time
        XCTAssertTrue(
            PlayDistribution.shares(entries: entries, metric: .playtime, axis: .family).isEmpty)
    }
}
