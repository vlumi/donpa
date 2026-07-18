import DonpaCore
import Foundation

/// The QR byte budget — the encoder yields nothing past ~2.3KB, so an
/// oversized card must shrink DETERMINISTICALLY: membership is a pure
/// function of the record. Ranking: won before unwon, more wins first,
/// faster best, then key. Shrink order: unwon configs → daily window
/// 14→7 → career → largest ranked prefix (binary search) → daily 0.
/// The LINK always keeps the full payload; only the QR is budgeted.
enum ShareQRBudget {
    struct Plan: Equatable {
        let scores: [SharedConfigScore]
        let dailyDays: Int
        /// Rides only while the player's toggle is on; the budget can only
        /// take it away.
        let career: Bool
    }

    static let fullDailyWindow = 14
    static let reducedDailyWindow = 7

    /// The relevance ranking — a total order.
    static func ranked(_ scores: [SharedConfigScore]) -> [SharedConfigScore] {
        scores.sorted { a, b in
            let aWon = a.wins > 0
            let bWon = b.wins > 0
            if aWon != bWon { return aWon }
            if a.wins != b.wins { return a.wins > b.wins }
            switch (a.best, b.best) {
            case (let x?, let y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.key < b.key
            }
        }
    }

    /// The first plan (in the shrink order above) that `encode` accepts.
    /// Payload order stays key-sorted (the codec's determinism rule); the
    /// ranking only decides membership.
    static func firstFitting(
        scores: [SharedConfigScore], career: Bool, encode: (Plan) -> URL?
    ) -> URL? {
        let byKey = { (list: [SharedConfigScore]) in list.sorted { $0.key < $1.key } }
        let won = ranked(scores).filter { $0.wins > 0 }

        let steps: [Plan] = [
            Plan(scores: byKey(scores), dailyDays: fullDailyWindow, career: career),
            Plan(scores: byKey(won), dailyDays: fullDailyWindow, career: career),
            Plan(scores: byKey(won), dailyDays: reducedDailyWindow, career: career),
            Plan(scores: byKey(won), dailyDays: reducedDailyWindow, career: false),
        ]
        for step in steps {
            if let url = encode(step) { return url }
        }
        for days in [reducedDailyWindow, 0] {
            if let url = largestFittingPrefix(of: won, dailyDays: days, encode: encode) {
                return url
            }
        }
        return nil
    }

    /// The longest ranked prefix that encodes at `dailyDays` — fit is
    /// monotone in prefix length, so binary search is sound.
    private static func largestFittingPrefix(
        of ranked: [SharedConfigScore], dailyDays: Int, encode: (Plan) -> URL?
    ) -> URL? {
        var low = 0  // empty payload always encodes; keep as the floor
        var high = ranked.count
        var best: URL?
        while low <= high {
            let mid = (low + high) / 2
            let plan = Plan(
                scores: Array(ranked.prefix(mid)).sorted { $0.key < $1.key },
                dailyDays: dailyDays, career: false)
            if let url = encode(plan) {
                best = url
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return best
    }
}
