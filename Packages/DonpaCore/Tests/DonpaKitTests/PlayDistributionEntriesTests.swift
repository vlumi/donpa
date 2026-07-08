import DonpaCore
import XCTest

@testable import DonpaKit

/// The breakdown bars' entry sweep: every family's records must reach the
/// aggregation (Drills was silently missing — the sweep hardcoded the family
/// list), and edge-agnostic families must not be double-counted.
final class PlayDistributionEntriesTests: XCTestCase {
    @MainActor
    private func scoreboard(playing configs: [GameConfig]) -> Scoreboard {
        let defaults = UserDefaults(suiteName: "PlayDistributionEntriesTests")!
        defaults.removePersistentDomain(forName: "PlayDistributionEntriesTests")
        let board = Scoreboard(defaults: defaults)
        for config in configs {
            board.recordGameOutcome(for: config, won: true, minesHit: 0, minesDisarmed: 1)
        }
        return board
    }

    @MainActor
    func testEveryFamilyReachesTheBars() {
        let board = scoreboard(playing: [
            .practice(.s), .basic(.beginner), .grid(.s, .normal, .flat),
            .hive(.s, .normal, .round),
        ])
        let entries = PlayDistributionView.entries(from: board)
        let families = Set(entries.map(\.config.family))
        XCTAssertEqual(families, [.practice, .basic, .grid, .hive])
        // Family shares include Drills.
        let shares = PlayDistribution.shares(entries: entries, metric: .games, axis: .family)
        XCTAssertTrue(shares.contains { $0.label == BoardFamily.practice.label })
    }

    @MainActor
    func testEdgeAgnosticFamiliesAreNotDoubleCounted() {
        let board = scoreboard(playing: [.practice(.s), .basic(.beginner)])
        let entries = PlayDistributionView.entries(from: board)
        // One entry per played config — the flat/round sweep must dedupe the
        // families whose keys ignore edges.
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.games), [1, 1])
    }
}
