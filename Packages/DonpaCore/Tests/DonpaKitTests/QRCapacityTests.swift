import DonpaCore
import XCTest

@testable import DonpaKit

/// A QR has a hard byte ceiling — a veteran's every-config payload overflows
/// it and `CIFilter` yields nothing, which silently hid the QR button. These
/// pin the failure mode and the score budget that keeps a QR encodable.
@MainActor
final class QRCapacityTests: XCTestCase {
    /// A payload the size of a long-time player's: enough configs that the
    /// unbudgeted URL exceeds QR capacity.
    private func veteranScores(configs: Int) -> [SharedConfigScore] {
        (0..<configs).map { i in
            SharedConfigScore(
                key: "v2|grid|flat|\(8 << (i % 8))x\(8 << (i % 8))|m\(100 + i)",
                best: 10_000 + i * 137, wins: 40 - (i % 30),
                bestProgress: 0.97, recentPace: 1.43, bestPace: 2.32)
        }
    }

    func testUnbudgetedVeteranPayloadOverflowsQR() throws {
        let identity = ShareIdentity()
        let payload = try identity.makePayload(
            name: "Veteran", scores: veteranScores(configs: 200),
            career: nil, issuedAt: Date(timeIntervalSince1970: 1_000_000))
        let url = try ShareLink.url(for: payload)
        // The reproduction: past the QR byte ceiling the encoder yields nil.
        XCTAssertNil(
            QRCode.ciImage(from: url.absoluteString),
            "if this ever FITS, the budget below can relax")
    }

    func testScoreBudgetKeepsQREncodable() throws {
        let identity = ShareIdentity()
        // The budget path: the same account capped like budgetedQR's floor.
        let all = veteranScores(configs: 200)
        let budgeted = Array(
            all.sorted { ($0.wins, $1.key) > ($1.wins, $0.key) }.prefix(10)
        ).sorted { $0.key < $1.key }
        let payload = try identity.makePayload(
            name: "Veteran", scores: budgeted,
            career: nil, issuedAt: Date(timeIntervalSince1970: 1_000_000))
        let url = try ShareLink.url(for: payload)
        XCTAssertNotNil(QRCode.ciImage(from: url.absoluteString))
        // The budget keeps the boards a rival cares about: the biggest win
        // counts survive.
        let minKeptWins = budgeted.map(\.wins).min() ?? 0
        let maxDroppedWins =
            all.filter { a in !budgeted.contains { $0.key == a.key } }.map(\.wins).max() ?? 0
        XCTAssertGreaterThanOrEqual(minKeptWins, maxDroppedWins)
    }
}
