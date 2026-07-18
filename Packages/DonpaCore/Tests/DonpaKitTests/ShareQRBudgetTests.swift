import DonpaCore
import XCTest

@testable import DonpaKit

/// The QR byte budget's policy — deterministic membership, documented shrink
/// order, and the real encoder's ceiling.
@MainActor
final class ShareQRBudgetTests: XCTestCase {
    private func score(
        _ key: String, wins: Int, best: Int? = nil, progress: Double? = nil
    ) -> SharedConfigScore {
        SharedConfigScore(
            key: key, best: best, wins: wins, bestProgress: progress,
            recentPace: nil, bestPace: nil)
    }

    private func veteran(_ configs: Int) -> [SharedConfigScore] {
        (0..<configs).map { i in
            score(
                "v2|grid|flat|\(8 << (i % 8))x\(8 << (i % 8))|m\(100 + i)",
                wins: 40 - (i % 30), best: 10_000 + i * 137, progress: 0.97)
        }
    }

    // MARK: Ranking

    func testRankingIsTotalAndByPolicy() {
        let unwon = score("z-unwon", wins: 0, progress: 0.9)
        let manyWins = score("m-many", wins: 30, best: 900)
        let fewWinsFast = score("a-fast", wins: 3, best: 100)
        let fewWinsSlow = score("b-slow", wins: 3, best: 200)
        let fewWinsSlowLaterKey = score("c-slow", wins: 3, best: 200)
        let ranked = ShareQRBudget.ranked(
            [unwon, fewWinsSlowLaterKey, fewWinsSlow, fewWinsFast, manyWins])
        XCTAssertEqual(
            ranked.map(\.key), ["m-many", "a-fast", "b-slow", "c-slow", "z-unwon"],
            "won before unwon; wins desc; best asc; key as final tiebreak")
        // Determinism: any shuffle ranks identically.
        let shuffled = ShareQRBudget.ranked(
            [fewWinsSlow, manyWins, unwon, fewWinsFast, fewWinsSlowLaterKey])
        XCTAssertEqual(shuffled.map(\.key), ranked.map(\.key))
    }

    // MARK: Shrink order (fake encoder = byte limit on the plan)

    /// A fake encoder charging bytes per score/day/career, accepting under `limit`.
    private func encoder(limit: Int) -> (ShareQRBudget.Plan) -> URL? {
        { plan in
            let cost = plan.scores.count * 40 + plan.dailyDays * 12 + (plan.career ? 200 : 0)
            return cost <= limit ? URL(string: "donpa://fits/\(plan.scores.count)") : nil
        }
    }

    func testShrinkDropsUnwonFirstThenDaysThenCareer() {
        let scores = [
            score("a", wins: 5, best: 100), score("b", wins: 2, best: 200),
            score("u1", wins: 0, progress: 0.5), score("u2", wins: 0, progress: 0.6),
        ]
        // Fits only once the unwon pair is gone: 2×40 + 14×12 + 200 = 448.
        XCTAssertNotNil(
            ShareQRBudget.firstFitting(scores: scores, career: true, encode: encoder(limit: 450)))
        // Tighter: needs the 7-day window too (2×40 + 7×12 + 200 = 364).
        XCTAssertNotNil(
            ShareQRBudget.firstFitting(scores: scores, career: true, encode: encoder(limit: 370)))
        // Tighter still: career must go (2×40 + 7×12 = 164).
        let noCareer = ShareQRBudget.firstFitting(
            scores: scores, career: true, encode: encoder(limit: 200))
        XCTAssertNotNil(noCareer)
        // And the prefix search floor: one score, no daily (1×40 + 0 = 40).
        XCTAssertEqual(
            ShareQRBudget.firstFitting(scores: scores, career: true, encode: encoder(limit: 45)),
            URL(string: "donpa://fits/1"))
    }

    func testPrefixKeepsTheMostWonBoards() {
        let scores = veteran(30)
        // Budget that fits ~10 scores with 7 days: 10×40 + 7×12 = 484.
        let url = ShareQRBudget.firstFitting(
            scores: scores, career: false, encode: encoder(limit: 490))
        XCTAssertEqual(url, URL(string: "donpa://fits/10"))
    }

    // MARK: The real ceiling

    func testRealEncoderOverflowsAndBudgetRecovers() throws {
        let identity = ShareIdentity()
        let all = veteran(200)
        let full = try identity.makePayload(
            name: "Veteran", scores: all, career: nil,
            issuedAt: Date(timeIntervalSince1970: 1_000_000))
        let fullURL = try ShareLink.url(for: full)
        XCTAssertNil(
            QRCode.ciImage(from: fullURL.absoluteString),
            "if 200 configs ever FIT a QR, the policy can relax")

        let budgeted = ShareQRBudget.firstFitting(scores: all, career: false) { plan in
            guard
                let payload = try? identity.makePayload(
                    name: "Veteran", scores: plan.scores, career: nil,
                    issuedAt: Date(timeIntervalSince1970: 1_000_000)),
                let url = try? ShareLink.url(for: payload),
                QRCode.ciImage(from: url.absoluteString) != nil
            else { return nil }
            return url
        }
        XCTAssertNotNil(budgeted, "the budget must always find an encodable card")
    }
}
