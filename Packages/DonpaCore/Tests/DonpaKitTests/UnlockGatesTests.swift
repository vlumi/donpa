import DonpaCore
import XCTest

@testable import DonpaKit

/// The picker-side gating wrapper: nil records = open surface, real records
/// gate through the engine, and the Settings "Unlock all boards" bypass
/// overrides WITHOUT storing anything — flipping it off returns to whatever
/// the records derive.
final class UnlockGatesTests: XCTestCase {

    /// Records holding one win on each given config (the engine-test fixture).
    private func won(_ configs: GameConfig...) -> [String: ScoreRecord] {
        var records: [String: ScoreRecord] = [:]
        for config in configs {
            var record = ScoreRecord()
            record.wins.add(1)
            records[config.storageKey] = record
        }
        return records
    }

    func testNilRecordsMeansOpenSurface() {
        let gates = UnlockGates.open
        XCTAssertTrue(gates.size(.xxxl))
        XCTAssertTrue(gates.rank(.lunatic))
        XCTAssertTrue(gates.family(.hive))
        XCTAssertTrue(gates.edges(.round))
    }

    func testFreshRecordsGateTheTopOfTheLadder() {
        let gates = UnlockGates(records: [:])
        XCTAssertTrue(gates.size(.m))  // starting matrix
        XCTAssertFalse(gates.size(.l))
        XCTAssertFalse(gates.family(.hive))
        XCTAssertFalse(gates.edges(.round))
    }

    func testBypassAllOverridesGatesWithoutTouchingRecords() {
        let records: [String: ScoreRecord] = [:]
        let bypassed = UnlockGates(records: records, bypassAll: true)
        XCTAssertTrue(bypassed.size(.xxxl))
        XCTAssertTrue(bypassed.rank(.lunatic))
        XCTAssertTrue(bypassed.family(.hive))
        XCTAssertTrue(bypassed.edges(.round))
        XCTAssertTrue(bypassed.config(.hive(.xxxl, .insane, .round)))

        // Untoggling returns to the records' verdict — nothing was stored.
        let restored = UnlockGates(records: records, bypassAll: false)
        XCTAssertFalse(restored.size(.l))
        XCTAssertFalse(restored.family(.hive))
    }
}
