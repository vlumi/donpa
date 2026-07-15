import XCTest

@testable import DonpaCore

/// The v3 `daily` window: codec round-trip, hostile-input guards, and the
/// receiver's per-date accumulation.
final class SharingDailyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func day(
        _ key: String, best: Int? = nil, threeBV: Int? = nil, progress: Double? = nil,
        attempts: Int = 1
    ) -> SharedDailyDay {
        SharedDailyDay(
            key: key, best: best, threeBV: threeBV, progress: progress, attempts: attempts)
    }

    private func payload(
        daily: [SharedDailyDay]?, id: ShareIdentity = ShareIdentity(), issuedAt: Date? = nil
    ) throws -> SharePayload {
        try id.makePayload(
            name: "Ville", scores: [], career: nil, daily: daily, issuedAt: issuedAt ?? t0)
    }

    func testDailyWindowRoundTrips() throws {
        let daily = [
            day("2026-07-20", best: 1234, threeBV: 40, attempts: 3),
            day("2026-07-21", progress: 0.6),
        ]
        let p = try payload(daily: daily)
        let back = try ShareCodec.decode(fromString: try ShareCodec.encodeToString(p))
        XCTAssertEqual(back.body.daily, daily)
        XCTAssertEqual(back.body.daily?.first?.pace, 40 * 100 / 1234.0)
    }

    func testV2PayloadWithoutDailyStillDecodes() throws {
        // An old sender: envelope v2, no daily field. Absent optionals
        // re-encode identically, so the v2 signature holds.
        let p = try payload(daily: nil)
        let v2 = SharePayload(
            version: 2, publicKey: p.publicKey, signature: p.signature, body: p.body)
        let back = try ShareCodec.decode(try ShareCodec.encode(v2))
        XCTAssertNil(back.body.daily)
    }

    func testHostileDailyRejected() throws {
        let bad: [[SharedDailyDay]] = [
            // Non-canonical key: parses, but Calendar rolls it over — not a real day.
            [day("2026-07-99")],
            [day("not-a-date")],
            [day("2026-07-20", best: 100, threeBV: 5), day("2026-07-20", best: 90, threeBV: 5)],
            [day("2026-07-20", best: -1, threeBV: 5)],
            [day("2026-07-20", progress: 1.5)],
            [day("2026-07-20", attempts: -1)],
        ]
        for daily in bad {
            XCTAssertThrowsError(
                try ShareCodec.sanitize(
                    ShareBody(name: "x", scores: [], career: nil, daily: daily, issuedAt: t0)),
                "\(daily)"
            ) {
                XCTAssertEqual($0 as? ShareCodec.DecodeError, .malformed)
            }
        }
    }

    func testFriendAccumulatesDailiesPerDate() throws {
        let id = ShareIdentity()
        let first = try payload(
            daily: [
                day("2026-07-20", best: 1000, threeBV: 40, attempts: 2),
                day("2026-07-21", progress: 0.4),
            ],
            id: id)
        let friend = FriendMerge.friend(from: first, existing: nil, now: t0)
        XCTAssertEqual(friend.dailies.count, 2)

        // The next card's window covers 21–22: it wins 21, 20 survives.
        let second = try payload(
            daily: [
                day("2026-07-21", best: 800, threeBV: 30, attempts: 3),
                day("2026-07-22", progress: 0.9),
            ],
            id: id, issuedAt: t0.addingTimeInterval(86_400))
        let updated = FriendMerge.friend(from: second, existing: friend, now: t0)
        XCTAssertEqual(updated.dailies.count, 3)
        XCTAssertEqual(updated.dailies["2026-07-20"]?.best, 1000, "outside the window survives")
        XCTAssertEqual(updated.dailies["2026-07-21"]?.best, 800, "the newest card wins its dates")
    }
}
