import Foundation
import XCTest

@testable import DonpaCore

/// Test shorthand: a full win = time submission + outcome tally, mirroring the
/// app's paired calls (the win TALLY lives on the outcome side, so a daily
/// clear counts as a win without submitting a time).
extension Scoreboard {
    @discardableResult
    func submitWin(
        _ centiseconds: Int, for config: GameConfig, at date: Date = Date(),
        threeBV: Int? = nil
    ) -> Bool {
        let isRecord = submit(centiseconds, for: config, at: date, threeBV: threeBV)
        recordGameOutcome(
            for: config, won: true, minesHit: 0, minesDisarmed: config.mineCount, at: date)
        return isRecord
    }
}
