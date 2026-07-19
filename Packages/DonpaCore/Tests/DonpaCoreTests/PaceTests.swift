import XCTest

@testable import DonpaCore

/// 3BV and the pace window — the raw material of the skill-rank spec.
final class PaceTests: XCTestCase {
    // MARK: 3BV

    /// A mine-free board is ONE opening: a single tap clears everything.
    func testMineFreeBoardIsOneTap() {
        let board = Board(topology: BoundedSquareTopology(width: 5, height: 5))
        XCTAssertEqual(Pace.threeBV(of: board), 1)
    }

    /// One corner mine: no zero cell touches it, so the rest is one opening
    /// plus the numbered cells around the mine — which the flood's border
    /// takes for free. 5×5, mine at (0,0): the zero region's border covers
    /// every number → 1 tap.
    func testCornerMineStillOneTap() {
        var board = Board(topology: BoundedSquareTopology(width: 5, height: 5))
        board.placeMines(at: Set([Coord(0, 0)]))
        XCTAssertEqual(Pace.threeBV(of: board), 1)
    }

    /// A full mine wall down the middle splits two openings → 2 taps.
    func testWallSplitsTwoOpenings() {
        var board = Board(topology: BoundedSquareTopology(width: 5, height: 5))
        board.placeMines(at: Set((0..<5).map { Coord(2, $0) }))
        XCTAssertEqual(Pace.threeBV(of: board), 2)
    }

    /// Dense enough that no zero cell exists: every safe cell is its own tap.
    /// 2×2 with one mine: the three safe cells all touch it → 3 taps.
    func testNoOpeningsCountsEverySafeCell() {
        var board = Board(topology: BoundedSquareTopology(width: 2, height: 2))
        board.placeMines(at: Set([Coord(0, 0)]))
        XCTAssertEqual(Pace.threeBV(of: board), 3)
    }

    /// A numbered cell NOT adjacent to any opening needs its own tap: 1×4
    /// with a mine at the end — cells at distance 1 and 2 are numbered (no
    /// zero neighbor on the mine side), the far cell is a zero opening whose
    /// border takes the distance-2 number.
    func testIsolatedNumberNeedsItsOwnTap() {
        var board = Board(topology: BoundedSquareTopology(width: 4, height: 1))
        board.placeMines(at: Set([Coord(0, 0)]))
        // (1,0)=1, (2,0)=0? — (2,0) neighbors are (1,0),(3,0): no mine → 0.
        // Opening at (2,0)+(3,0) takes border (1,0) for free → 1 tap total.
        XCTAssertEqual(Pace.threeBV(of: board), 1)
    }

    /// Hex adjacency changes the answer: the same definition rides the
    /// board's own topology (sanity: mine-free hex is still one tap).
    func testHexMineFreeIsOneTap() {
        let board = Board(topology: HexTopology(width: 4, height: 4))
        XCTAssertEqual(Pace.threeBV(of: board), 1)
    }

    /// Wrapped boards fold the seam: a corner mine's numbered ring wraps but
    /// the single opening still clears the rest in one tap.
    func testWrappedMineFreeIsOneTap() {
        let board = Board(topology: WrappedSquareTopology(width: 5, height: 5))
        XCTAssertEqual(Pace.threeBV(of: board), 1)
    }

    // MARK: Pace values

    func testPaceIsThreeBVPerSecond() {
        let win = RecentWin(date: .init(), centiseconds: 10_000, threeBV: 50)
        XCTAssertEqual(win.pace, 0.5, accuracy: 1e-9)  // 50 taps / 100 s
    }

    /// A 0.00 s clear (single-tap XS, clock truncated to zero) clamps to one
    /// centisecond — the FASTEST reading, never a zero that ranks slowest.
    func testInstantWinClampsUpNotDown() {
        let instant = RecentWin(date: .init(), centiseconds: 0, threeBV: 1)
        XCTAssertEqual(instant.pace, 100, accuracy: 1e-9)
    }

    // MARK: Ladder lines

    private func recordWithWin(pace: Double, threeBV: Int = 100) -> ScoreRecord {
        var record = ScoreRecord()
        record.wins.add(1)
        record.recentWins = [
            RecentWin(
                date: Date(timeIntervalSince1970: 0),
                centiseconds: Int(Double(threeBV) * 100 / pace), threeBV: threeBV)
        ]
        return record
    }

    func testLadderLightsOnlyWithEveryGateSizeLogged() {
        var records: [String: ScoreRecord] = [:]
        for size in [BoardSize.xs, .s, .m] {
            records[GameConfig.grid(size, .normal, .flat).storageKey] =
                recordWithWin(pace: 2)
        }
        // L missing → dark, even with an XL win logged.
        records[GameConfig.grid(.xl, .normal, .flat).storageKey] = recordWithWin(pace: 3)
        XCTAssertNil(
            Pace.ladderPace(records: records, family: .grid, density: .normal, edges: .flat))

        records[GameConfig.grid(.l, .normal, .flat).storageKey] = recordWithWin(pace: 2)
        XCTAssertNotNil(
            Pace.ladderPace(records: records, family: .grid, density: .normal, edges: .flat))
    }

    func testLadderUnionIncludesUnrequiredBigBoards() {
        var records: [String: ScoreRecord] = [:]
        for size in Pace.gateSizes {
            records[GameConfig.grid(size, .normal, .flat).storageKey] =
                recordWithWin(pace: 2, threeBV: 10)
        }
        // A heavy XXXL win dominates the 3BV-weighted median.
        records[GameConfig.grid(.xxxl, .normal, .flat).storageKey] =
            recordWithWin(pace: 5, threeBV: 10_000)
        let pace = Pace.ladderPace(
            records: records, family: .grid, density: .normal, edges: .flat)
        XCTAssertEqual(pace ?? 0, 5, accuracy: 0.01)
    }

    func testLadderScopesByEdgesAndDensity() {
        var records: [String: ScoreRecord] = [:]
        for size in Pace.gateSizes {
            records[GameConfig.grid(size, .normal, .flat).storageKey] =
                recordWithWin(pace: 2)
        }
        XCTAssertNil(
            Pace.ladderPace(records: records, family: .grid, density: .normal, edges: .round))
        XCTAssertNil(
            Pace.ladderPace(records: records, family: .grid, density: .easy, edges: .flat))
    }

    func testDrillsLadderGatesOnItsFullRange() {
        var records: [String: ScoreRecord] = [:]
        for size in [BoardSize.xs, .s, .m, .l] {
            records[GameConfig.practice(size).storageKey] = recordWithWin(pace: 2)
        }
        XCTAssertNil(
            Pace.ladderPace(records: records, family: .practice, density: nil, edges: .flat))
        records[GameConfig.practice(.xl).storageKey] = recordWithWin(pace: 2)
        XCTAssertNotNil(
            Pace.ladderPace(records: records, family: .practice, density: nil, edges: .flat))
    }

    func testBasicHasNoLadder() {
        XCTAssertNil(
            Pace.ladderPace(records: [:], family: .basic, density: nil, edges: .flat))
    }

    /// Weighted median: the big board's pace dominates the tiny one's noise.
    func testMedianPaceWeightsByThreeBV() {
        let noisy = RecentWin(date: .init(), centiseconds: 100, threeBV: 2)  // 2.0/s
        let solid = RecentWin(date: .init(), centiseconds: 20_000, threeBV: 100)  // 0.5/s
        XCTAssertEqual(Pace.medianPace(of: [noisy, solid])!, 0.5, accuracy: 1e-9)
        XCTAssertNil(Pace.medianPace(of: []))
    }

    // MARK: The rolling log

    @MainActor private func freshBoard() -> Scoreboard {
        let suite = "pace-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return Scoreboard(defaults: defaults)
    }

    @MainActor func testSubmitAppendsNewestFirstAndTrims() {
        let board = freshBoard()
        for i in 0..<12 {
            board.submitWin(
                10_000 + i, for: GameConfig.beginner,
                at: Date(timeIntervalSince1970: TimeInterval(1000 + i)), threeBV: 40)
        }
        let wins = board.displayRecords[GameConfig.beginner.storageKey]!.recentWins
        XCTAssertEqual(wins.count, ScoreRecord.recentWinLimit)
        XCTAssertEqual(wins.first?.centiseconds, 10_011)  // newest first
        XCTAssertEqual(wins.last?.centiseconds, 10_002)  // oldest two trimmed
    }

    @MainActor func testSubmitWithoutThreeBVLogsNothing() {
        let board = freshBoard()
        board.submitWin(10_000, for: GameConfig.beginner)
        XCTAssertTrue(
            board.displayRecords[GameConfig.beginner.storageKey]!.recentWins.isEmpty)
    }

    // MARK: Best pace

    @MainActor func testBestPaceKeepsTheFastest() {
        let board = freshBoard()
        board.submitWin(10_000, for: GameConfig.beginner, threeBV: 50)  // 0.5/s
        board.submitWin(5_000, for: GameConfig.beginner, threeBV: 40)  // 0.8/s
        board.submitWin(10_000, for: GameConfig.beginner, threeBV: 40)  // 0.4/s — slower
        let best = board.displayRecords[GameConfig.beginner.storageKey]!.bestPace
        XCTAssertEqual(best?.pace ?? 0, 0.8, accuracy: 1e-9)
    }

    func testBestPaceMergesCrossDeviceMax() {
        var own = ScoreRecord()
        own.bestPace = RecentWin(date: .init(), centiseconds: 10_000, threeBV: 50)  // 0.5
        var other = ScoreRecord()
        other.bestPace = RecentWin(date: .init(), centiseconds: 5_000, threeBV: 40)  // 0.8
        let merged = StatsMerge.merge(mine: ["k": own], others: ["dev2": ["k": other]])
        XCTAssertEqual(merged["k"]?.bestPace?.pace ?? 0, 0.8, accuracy: 1e-9)
    }

    // MARK: Merge

    func testMergedRecentUnionsDedupsAndCaps() {
        func win(_ t: TimeInterval) -> RecentWin {
            RecentWin(date: Date(timeIntervalSince1970: t), centiseconds: 5000, threeBV: 30)
        }
        let own = [win(10), win(8), win(6)]
        let other = [win(9), win(8), win(7)]  // win(8) duplicates own's
        let merged = StatsMerge.mergedRecent(own, [other])
        XCTAssertEqual(
            merged.map(\.date.timeIntervalSince1970), [10, 9, 8, 7, 6],
            "union, deduped, newest first")

        let flood = (0..<20).map { win(TimeInterval(100 + $0)) }
        XCTAssertEqual(
            StatsMerge.mergedRecent(flood, []).count, ScoreRecord.recentWinLimit)
    }

    // MARK: Forward compatibility

    /// An old record (no recentWins key) decodes with an empty window.
    func testOldRecordDecodesWithoutTheField() throws {
        var record = ScoreRecord()
        record.recentWins = [RecentWin(date: .init(), centiseconds: 1, threeBV: 1)]
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(record)) as? [String: Any])
        json.removeValue(forKey: "recentWins")
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(ScoreRecord.self, from: data)
        XCTAssertTrue(decoded.recentWins.isEmpty)
    }
}
