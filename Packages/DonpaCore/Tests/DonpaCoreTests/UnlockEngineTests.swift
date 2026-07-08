import XCTest

@testable import DonpaCore

/// The gating predicate: what a fresh install sees, how wins climb the ladders,
/// the Basic/Drills credit rules, and the veteran auto-pass. Pure function —
/// records in, access out.
final class UnlockEngineTests: XCTestCase {

    /// Records holding one win on each given config.
    private func won(_ configs: GameConfig...) -> [String: ScoreRecord] {
        var records: [String: ScoreRecord] = [:]
        for config in configs {
            var record = ScoreRecord()
            record.wins.add(1)
            records[config.storageKey] = record
        }
        return records
    }

    // MARK: Fresh install

    func testFreshInstallStartingMatrix() {
        let none: [String: ScoreRecord] = [:]
        // Sizes: XS/S/M open, the rest locked.
        XCTAssertTrue(UnlockEngine.sizeUnlocked(.xs, records: none))
        XCTAssertTrue(UnlockEngine.sizeUnlocked(.m, records: none))
        XCTAssertFalse(UnlockEngine.sizeUnlocked(.l, records: none))
        XCTAssertFalse(UnlockEngine.sizeUnlocked(.xxxl, records: none))
        // Ranks: Trainee/Sapper open.
        XCTAssertTrue(UnlockEngine.rankUnlocked(.easy, records: none))
        XCTAssertTrue(UnlockEngine.rankUnlocked(.normal, records: none))
        XCTAssertFalse(UnlockEngine.rankUnlocked(.hard, records: none))
        XCTAssertFalse(UnlockEngine.rankUnlocked(.lunatic, records: none))
        // Families: only Hive gates; edges: only Round gates.
        XCTAssertTrue(UnlockEngine.familyUnlocked(.practice, records: none))
        XCTAssertTrue(UnlockEngine.familyUnlocked(.basic, records: none))
        XCTAssertTrue(UnlockEngine.familyUnlocked(.grid, records: none))
        XCTAssertFalse(UnlockEngine.familyUnlocked(.hive, records: none))
        XCTAssertTrue(UnlockEngine.edgesUnlocked(.flat, records: none))
        XCTAssertFalse(UnlockEngine.edgesUnlocked(.round, records: none))
        // A whole config ANDs its axes.
        XCTAssertTrue(UnlockEngine.unlocked(.grid(.m, .normal, .flat), records: none))
        XCTAssertFalse(UnlockEngine.unlocked(.grid(.l, .normal, .flat), records: none))
        XCTAssertFalse(UnlockEngine.unlocked(.grid(.m, .hard, .flat), records: none))
        XCTAssertFalse(UnlockEngine.unlocked(.grid(.m, .normal, .round), records: none))
        XCTAssertFalse(UnlockEngine.unlocked(.hive(.s, .normal, .flat), records: none))
        XCTAssertTrue(UnlockEngine.unlocked(.practice(.m), records: none))
        XCTAssertTrue(UnlockEngine.unlocked(.basic(.expert), records: none))
    }

    // MARK: Size ladder

    func testSizeLadderClimbsOneRungPerWin() {
        let mWin = won(.grid(.m, .normal, .flat))
        XCTAssertTrue(UnlockEngine.sizeUnlocked(.l, records: mWin))
        XCTAssertFalse(UnlockEngine.sizeUnlocked(.xl, records: mWin))
        let lWin = won(.grid(.l, .normal, .flat))
        XCTAssertTrue(UnlockEngine.sizeUnlocked(.xl, records: lWin))
        XCTAssertFalse(UnlockEngine.sizeUnlocked(.xxl, records: lWin))
    }

    func testEscapeHatchWinAboveTheRungIsMonotone() {
        // A rival's XL board won via head-to-head: everything at or below the
        // XL-win's reach opens (L needs ≥M, XL needs ≥L, XXL needs ≥XL — all
        // satisfied); XXXL still needs a XXL win.
        let xlWin = won(.grid(.xl, .normal, .flat))
        XCTAssertTrue(UnlockEngine.sizeUnlocked(.l, records: xlWin))
        XCTAssertTrue(UnlockEngine.sizeUnlocked(.xl, records: xlWin))
        XCTAssertTrue(UnlockEngine.sizeUnlocked(.xxl, records: xlWin))
        XCTAssertFalse(UnlockEngine.sizeUnlocked(.xxxl, records: xlWin))
    }

    func testDrillsWinsClimbTheSizeLadder() {
        // The practice range trains you up — a Drills M win opens L everywhere.
        let drillsM = won(.practice(.m))
        XCTAssertTrue(UnlockEngine.sizeUnlocked(.l, records: drillsM))
        XCTAssertTrue(UnlockEngine.unlocked(.practice(.l), records: drillsM))
        XCTAssertTrue(UnlockEngine.unlocked(.grid(.l, .normal, .flat), records: drillsM))
    }

    // MARK: Rank ladder

    func testRankLadderNeedsAtLeastSmall() {
        // An XS Sapper win credits no rank (XS is below the ≥S floor)…
        XCTAssertFalse(
            UnlockEngine.rankUnlocked(.hard, records: won(.grid(.xs, .normal, .flat))))
        // …an S Sapper win opens Veteran, and only Veteran.
        let sSapper = won(.grid(.s, .normal, .flat))
        XCTAssertTrue(UnlockEngine.rankUnlocked(.hard, records: sSapper))
        XCTAssertFalse(UnlockEngine.rankUnlocked(.brutal, records: sSapper))
        // The full walk up to Lunatic.
        XCTAssertTrue(
            UnlockEngine.rankUnlocked(.lunatic, records: won(.hive(.s, .insane, .flat))))
    }

    func testDrillsAndBasicNeverAdvanceTheRankLadder() {
        // Neither has a rank axis — no density credit no matter the size.
        let records = won(.practice(.xl), .basic(.expert))
        XCTAssertFalse(UnlockEngine.rankUnlocked(.hard, records: records))
    }

    // MARK: Hive + Round gates

    func testHiveOpensOnAnySquareFamilyWin() {
        XCTAssertTrue(UnlockEngine.familyUnlocked(.hive, records: won(.practice(.xs))))
        XCTAssertTrue(UnlockEngine.familyUnlocked(.hive, records: won(.basic(.beginner))))
        XCTAssertTrue(
            UnlockEngine.familyUnlocked(.hive, records: won(.grid(.xs, .easy, .flat))))
        // A hive win (escape hatch) does NOT open the hive gate by itself.
        XCTAssertFalse(
            UnlockEngine.familyUnlocked(.hive, records: won(.hive(.s, .normal, .flat))))
    }

    func testRoundOpensOnAWinAtMOrLarger() {
        XCTAssertFalse(
            UnlockEngine.edgesUnlocked(.round, records: won(.grid(.s, .normal, .flat))))
        XCTAssertTrue(
            UnlockEngine.edgesUnlocked(.round, records: won(.practice(.m))))
        // Basic Expert maps to M — it opens Round too.
        XCTAssertTrue(UnlockEngine.edgesUnlocked(.round, records: won(.basic(.expert))))
    }

    // MARK: Basic mapping

    func testBasicPresetsMapToLadderSizes() {
        // Beginner = XS: no ladder progress (M is already open) and no Round.
        let beginner = won(.basic(.beginner))
        XCTAssertFalse(UnlockEngine.sizeUnlocked(.l, records: beginner))
        XCTAssertFalse(UnlockEngine.edgesUnlocked(.round, records: beginner))
        // Expert = M: opens L and Round.
        let expert = won(.basic(.expert))
        XCTAssertTrue(UnlockEngine.sizeUnlocked(.l, records: expert))
    }

    // MARK: Veteran auto-pass

    func testVeteranRecordsPassEverything() {
        // One win on every board in the universe → the whole matrix is open.
        var records: [String: ScoreRecord] = [:]
        for family in BoardFamily.allCases {
            for edges in BoardEdges.allCases {
                for config in GameConfig.configs(family: family, edges: edges) {
                    var record = ScoreRecord()
                    record.wins.add(1)
                    records[config.storageKey] = record
                }
            }
        }
        for family in BoardFamily.allCases {
            for edges in BoardEdges.allCases {
                for config in GameConfig.configs(family: family, edges: edges) {
                    XCTAssertTrue(
                        UnlockEngine.unlocked(config, records: records),
                        "\(config.fullLabel) should be open for a veteran")
                }
            }
        }
    }

    /// Losses alone unlock nothing — the gate is wins.
    func testLossesDoNotCredit() {
        var record = ScoreRecord()
        record.gamesPlayed.add(20)
        record.losses.add(20)
        let records = [GameConfig.grid(.m, .normal, .flat).storageKey: record]
        XCTAssertFalse(UnlockEngine.sizeUnlocked(.l, records: records))
    }

    // MARK: Requirements

    func testRequirementsDescribeTheGates() {
        XCTAssertNil(UnlockEngine.requirement(size: .m))
        XCTAssertEqual(UnlockEngine.requirement(size: .l), .winSize(.m))
        XCTAssertEqual(UnlockEngine.requirement(size: .xxxl), .winSize(.xxl))
        XCTAssertNil(UnlockEngine.requirement(rank: .normal))
        XCTAssertEqual(UnlockEngine.requirement(rank: .hard), .winRank(.normal))
        XCTAssertEqual(UnlockEngine.requirement(rank: .lunatic), .winRank(.insane))
        XCTAssertEqual(UnlockEngine.requirement(family: .hive), .winAnySquare)
        XCTAssertNil(UnlockEngine.requirement(family: .grid))
        XCTAssertEqual(UnlockEngine.requirement(edges: .round), .winAtLeastM)
        XCTAssertNil(UnlockEngine.requirement(edges: .flat))
    }
}
