import XCTest

@testable import DonpaCore

/// A2 of the progression spec: every feat's rule, floor, and tier bars. One
/// builder per fact shape; each test earns exactly what it names.
final class AchievementEngineTests: XCTestCase {

    private var records: [String: ScoreRecord] = [:]

    override func setUp() {
        super.setUp()
        records = [:]
    }

    private func win(_ config: GameConfig, times: Int = 1) {
        var record = records[config.storageKey] ?? ScoreRecord()
        record.wins.add(times)
        records[config.storageKey] = record
    }

    private func mutate(_ config: GameConfig, _ change: (inout ScoreRecord) -> Void) {
        var record = records[config.storageKey] ?? ScoreRecord()
        change(&record)
        records[config.storageKey] = record
    }

    private func earned() -> [AchievementID: Int] {
        AchievementEngine.derivable(records: records)
    }

    // MARK: Starters & identity

    func testWinFirstOnAnyFamilyIncludingDrills() {
        XCTAssertNil(earned()[.winFirst])
        win(.practice(.xs))
        XCTAssertEqual(earned()[.winFirst], 1)
    }

    func testDrillsGraduationNeedsExactlyDrillsL() {
        win(.practice(.m))
        win(.grid(.l, .normal, .flat))
        XCTAssertNil(earned()[.drillsL])
        win(.practice(.l))
        XCTAssertEqual(earned()[.drillsL], 1)
    }

    func testHiveAndRoundFirsts() {
        win(.grid(.m, .normal, .flat))
        XCTAssertNil(earned()[.hiveFirst])
        XCTAssertNil(earned()[.roundFirst])
        win(.hive(.xs, .easy, .flat))
        win(.grid(.s, .easy, .round))
        XCTAssertEqual(earned()[.hiveFirst], 1)
        XCTAssertEqual(earned()[.roundFirst], 1)
    }

    func testHornetsNestNeedsHiveInsaneAtM() {
        win(.hive(.s, .insane, .flat))  // below the size floor
        win(.grid(.m, .insane, .flat))  // right size, wrong family
        XCTAssertNil(earned()[.hiveInsane])
        win(.hive(.m, .insane, .flat))
        XCTAssertEqual(earned()[.hiveInsane], 1)
    }

    // MARK: Skill

    func testBareHandsRespectsTheFloor() {
        // No-flag wins below the floor (size or rank) don't count…
        mutate(.grid(.s, .hard, .flat)) {
            $0.noFlagWins.add(1)
            $0.wins.add(1)
        }
        mutate(.grid(.m, .easy, .flat)) {
            $0.noFlagWins.add(1)
            $0.wins.add(1)
        }
        XCTAssertNil(earned()[.purityNoFlag])
        // …≥ M Sapper does.
        mutate(.grid(.m, .normal, .flat)) {
            $0.noFlagWins.add(1)
            $0.wins.add(1)
        }
        XCTAssertEqual(earned()[.purityNoFlag], 1)
    }

    func testInsaneAndLunaticFloors() {
        win(.grid(.s, .insane, .flat))  // XS/S Insane is a lottery — no feat
        XCTAssertNil(earned()[.insaneWin])
        win(.grid(.m, .insane, .flat))
        XCTAssertEqual(earned()[.insaneWin], 1)
        XCTAssertNil(earned()[.lunaticWin])
        win(.grid(.xs, .lunatic, .flat))  // any size: the tier is the feat
        XCTAssertEqual(earned()[.lunaticWin], 1)
    }

    func testExpertSpeedLadderTiers() {
        mutate(.basic(.expert)) { $0.best = BestTime(centiseconds: 17_900, achievedAt: .init()) }
        XCTAssertEqual(earned()[.speedExpert], 1)  // < 180 s
        mutate(.basic(.expert)) { $0.best = BestTime(centiseconds: 11_900, achievedAt: .init()) }
        XCTAssertEqual(earned()[.speedExpert], 2)  // < 120 s
        mutate(.basic(.expert)) { $0.best = BestTime(centiseconds: 8_999, achievedAt: .init()) }
        XCTAssertEqual(earned()[.speedExpert], 3)  // < 90 s
        mutate(.basic(.expert)) { $0.best = BestTime(centiseconds: 18_000, achievedAt: .init()) }
        XCTAssertNil(earned()[.speedExpert])  // exactly 180 s misses "under"
    }

    // MARK: Luck (exact-boundary tiers, matching the in-game toast cuts)

    func testLuckLadderBoundaries() {
        mutate(.grid(.m, .normal, .flat)) {
            $0.luckiestGuess = LuckiestGuess(survival: 0.5, achievedAt: .init())
        }
        XCTAssertEqual(earned()[.luckCoinFlip], 1)
        XCTAssertNil(earned()[.luckLongShot])
        mutate(.grid(.m, .normal, .flat)) {
            $0.luckiestGuess = LuckiestGuess(survival: 1.0 / 3.0, achievedAt: .init())
        }
        XCTAssertEqual(earned()[.luckLongShot], 1)
        XCTAssertNil(earned()[.luckMiracle])
        mutate(.grid(.m, .normal, .flat)) {
            $0.luckiestGuess = LuckiestGuess(survival: 0.25, achievedAt: .init())
        }
        XCTAssertEqual(earned()[.luckMiracle], 1)
    }

    // MARK: Full-clear tie-ins

    func testFullClearSizeStopsAtL() {
        // Every rank at XL — above the one-sitting ceiling, no feat.
        for density in Density.allCases { win(.grid(.xl, density, .flat)) }
        XCTAssertNil(earned()[.fullClearSize])
        for density in Density.allCases { win(.grid(.s, density, .flat)) }
        XCTAssertEqual(earned()[.fullClearSize], 1)
    }

    func testTrifectaAndTimedTrifecta() {
        mutate(.basic(.beginner)) {
            $0.wins.add(1)
            $0.best = BestTime(centiseconds: 1_000, achievedAt: .init())
        }
        mutate(.basic(.intermediate)) {
            $0.wins.add(1)
            $0.best = BestTime(centiseconds: 8_000, achievedAt: .init())
        }
        XCTAssertNil(earned()[.trifecta])
        mutate(.basic(.expert)) {
            $0.wins.add(1)
            $0.best = BestTime(centiseconds: 21_000, achievedAt: .init())
        }
        XCTAssertEqual(earned()[.trifecta], 1)
        // 10 + 80 + 210 s = 300 s — NOT under 5:00.
        XCTAssertNil(earned()[.trifectaTime])
        mutate(.basic(.expert)) { $0.best = BestTime(centiseconds: 20_999, achievedAt: .init()) }
        XCTAssertEqual(earned()[.trifectaTime], 1)
    }

    // MARK: Milestones

    func testMilestoneTiersSumAcrossFamilies() {
        win(.practice(.s), times: 6)  // Drills counts toward milestones
        win(.grid(.s, .normal, .flat), times: 4)
        XCTAssertEqual(earned()[.milesWins], 1)  // 10
        win(.hive(.s, .normal, .flat), times: 90)
        XCTAssertEqual(earned()[.milesWins], 2)  // 100 = silver; gold waits at 1000
        XCTAssertNil(earned()[.milesTiles])
        mutate(.grid(.m, .normal, .flat)) { $0.tilesOpened.add(100_000) }
        XCTAssertEqual(earned()[.milesTiles], 2)  // 10k bronze + 100k silver
        mutate(.grid(.m, .normal, .flat)) { $0.minesDisarmed.add(10_000) }
        XCTAssertEqual(earned()[.milesDisarmed], 2)
    }

    func testMilesWinsGold() {
        win(.grid(.s, .normal, .flat), times: 1000)
        XCTAssertEqual(earned()[.milesWins], 3)
    }

    // MARK: Progress (the detail view's live "current value")

    func testProgressReportsTrackedValues() {
        win(.grid(.s, .normal, .flat), times: 42)
        mutate(.grid(.m, .normal, .flat)) {
            $0.tilesOpened.add(1234)
            $0.minesDisarmed.add(56)
            $0.luckiestGuess = LuckiestGuess(survival: 0.2, achievedAt: .init())
        }
        mutate(.basic(.expert)) { $0.best = BestTime(centiseconds: 11_900, achievedAt: .init()) }

        func progress(_ id: AchievementID) -> AchievementProgress? {
            AchievementEngine.progress(for: id, records: records)
        }
        XCTAssertEqual(progress(.milesWins), AchievementProgress(metric: .wins, current: 42))
        XCTAssertEqual(progress(.milesTiles), AchievementProgress(metric: .tiles, current: 1234))
        XCTAssertEqual(progress(.milesDisarmed), AchievementProgress(metric: .mines, current: 56))
        XCTAssertEqual(
            progress(.speedExpert), AchievementProgress(metric: .bestSeconds, current: 11_900))
        // Luckiest survival rounded to a whole percent (0.2 → 20).
        XCTAssertEqual(
            progress(.luckCoinFlip), AchievementProgress(metric: .luckPercent, current: 20))
        // One-shots and hidden gags have no running number.
        XCTAssertNil(progress(.winFirst))
        XCTAssertNil(progress(.hiddenSecond))
    }

    func testProgressIsNilBeforeAnyData() {
        // No Expert best / no luck record yet → nothing to show.
        XCTAssertNil(AchievementEngine.progress(for: .speedExpert, records: records))
        XCTAssertNil(AchievementEngine.progress(for: .luckCoinFlip, records: records))
        // Counts start at zero (a valid running value, shown as "0 won").
        XCTAssertEqual(
            AchievementEngine.progress(for: .milesWins, records: records),
            AchievementProgress(metric: .wins, current: 0))
    }

    // MARK: Momentary (hidden)

    private func event(
        won: Bool, time: Int = 5_000, progress: Double = 0.5, actions: Int = 10
    ) -> GameEndEvent {
        GameEndEvent(
            config: .grid(.s, .normal, .flat), won: won, timeCentiseconds: time,
            progress: progress, revealActions: actions, date: .init())
    }

    func testHiddenSecondReveal() {
        XCTAssertEqual(
            AchievementEngine.momentary(event(won: false, actions: 2)), [.hiddenSecond])
        XCTAssertTrue(AchievementEngine.momentary(event(won: false, actions: 3)).isEmpty)
        // A win on the second action isn't the gag; neither is a poisoned resume.
        XCTAssertTrue(AchievementEngine.momentary(event(won: true, actions: 2)).isEmpty)
        XCTAssertTrue(
            AchievementEngine.momentary(
                event(won: false, actions: GameViewModel.restoredActionsPoison)
            ).isEmpty)
    }

    func testHiddenThirteenIsTheWholeSecond() {
        XCTAssertEqual(
            AchievementEngine.momentary(event(won: true, time: 1_300)), [.hiddenThirteen])
        XCTAssertEqual(
            AchievementEngine.momentary(event(won: true, time: 1_399)), [.hiddenThirteen])
        XCTAssertTrue(AchievementEngine.momentary(event(won: true, time: 1_400)).isEmpty)
        XCTAssertTrue(AchievementEngine.momentary(event(won: false, time: 1_350)).isEmpty)
    }

    func testHiddenSoCloseAndOvertime() {
        XCTAssertEqual(
            AchievementEngine.momentary(event(won: false, progress: 0.99)), [.hiddenSoClose])
        XCTAssertTrue(
            AchievementEngine.momentary(event(won: false, progress: 0.989)).isEmpty)
        XCTAssertEqual(
            AchievementEngine.momentary(event(won: true, time: 99_901)), [.hiddenOvertime])
        XCTAssertTrue(AchievementEngine.momentary(event(won: true, time: 99_900)).isEmpty)
    }

    // MARK: Shape

    func testIDsAreStableAndUnique() {
        let raw = AchievementID.allCases.map(\.rawValue)
        XCTAssertEqual(raw.count, Set(raw).count)
        XCTAssertEqual(AchievementID.allCases.count, 22)
        // Exactly the four gags hide until earned.
        XCTAssertEqual(
            AchievementID.allCases.filter(\.isHidden),
            [.hiddenSecond, .hiddenThirteen, .hiddenSoClose, .hiddenOvertime])
        // The wire values the ASC definitions will be built from — locked.
        XCTAssertEqual(AchievementID.winFirst.rawValue, "win.first")
        XCTAssertEqual(AchievementID.hiveInsane.rawValue, "hive.insane")
        XCTAssertEqual(AchievementID.speedExpert.tierThresholds, [180, 120, 90])
    }

    func testFreshRecordsEarnNothing() {
        XCTAssertTrue(earned().isEmpty)
    }
}
