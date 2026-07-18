import DonpaCore
import Foundation

/// Assembles a signed `SharePayload` from the scoreboard's MERGED cross-device
/// view (`displayRecords`), so a share reflects your true best, not just this
/// device's. `issuedAt` is the replay/downgrade guard.
@MainActor
enum SharePayloadBuilder {
    static func build(
        from scoreboard: Scoreboard, identity: ShareIdentity, name: String,
        includeCareer: Bool, daily: [SharedDailyDay]? = nil, now: Date
    ) -> SharePayload? {
        let career = includeCareer ? Self.career(from: scoreboard) : nil
        return try? identity.makePayload(
            name: name, scores: scores(from: scoreboard), career: career, daily: daily,
            issuedAt: now)
    }

    /// Every merged config's share slice, key-sorted (the codec's
    /// determinism rule).
    static func scores(from scoreboard: Scoreboard) -> [SharedConfigScore] {
        scoreboard.displayRecords.map { key, rec in
            SharedConfigScore(
                key: key,
                best: rec.best?.centiseconds,
                wins: rec.wins.total,
                bestProgress: rec.bestLossProgress,
                recentPace: Pace.medianPace(of: rec.recentWins),
                bestPace: rec.bestPace?.pace)
        }
        .sorted { $0.key < $1.key }
    }

    /// The daily slice for a share: the newest `days` (nil = the full
    /// history, for channels with no size budget), oldest-first so the
    /// payload stays deterministic. Nil when there's nothing to tell.
    static func dailyWindow(from dailyStore: DailyStore, days: Int?) -> [SharedDailyDay]? {
        var keys = dailyStore.displayRecords.keys.sorted()
        if let days { keys = keys.suffix(days) }
        let window = keys.compactMap { key -> SharedDailyDay? in
            guard let day = dailyStore.displayRecords[key] else { return nil }
            return SharedDailyDay(
                key: key, best: day.best?.centiseconds, threeBV: day.best?.threeBV,
                progress: day.bestProgress, attempts: day.attempts.total)
        }
        return window.isEmpty ? nil : window
    }

    /// Career totals summed across every merged config record — mirrors the
    /// `StatFigures(career:)` scope of the scoreboard's own career block.
    static func career(from scoreboard: Scoreboard) -> SharedCareer {
        let records = Array(scoreboard.displayRecords.values)
        func sum(_ f: (ScoreRecord) -> Int) -> Int { records.reduce(0) { $0 + f($1) } }
        return SharedCareer(
            gamesPlayed: sum { $0.gamesPlayed.total },
            wins: sum { $0.wins.total },
            noFlagWins: sum { $0.noFlagWins.total },
            noChordWins: sum { $0.noChordWins.total },
            tilesOpened: sum { $0.tilesOpened.total },
            flagsPlaced: sum { $0.flagsPlaced.total },
            minesDisarmed: sum { $0.minesDisarmed.total },
            minesHit: sum { $0.minesHit.total },
            chordsUsed: sum { $0.chordsUsed.total },
            playtimeCentiseconds: sum { $0.playtimeCentiseconds.total })
    }
}

extension SharePayloadBuilder {
    /// The ONE gate chain the share card, Nearby, and the keyboard zones all read.
    /// Nil without a trimmed name or an identity — the name IS the shared identity.
    /// The name is the sharer's own input; the RECEIVER sanitizes on decode.
    /// `dailyDays` sizes the daily slice to the channel: a rolling window
    /// for the QR/link (scan budget), nil = full history for Nearby.
    static func currentURL(
        scoreboard: Scoreboard, settings: Settings, identityStore: ShareIdentityStore,
        dailyStore: DailyStore, dailyDays: Int?
    ) -> URL? {
        if scoreboard.isCloudActive { scoreboard.refreshFromCloud() }
        let trimmed = settings.shareName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            let identity = identityStore.identity(),
            let payload = build(
                from: scoreboard, identity: identity, name: trimmed,
                includeCareer: settings.shareIncludeCareer,
                daily: dailyWindow(from: dailyStore, days: dailyDays), now: Date())
        else { return nil }
        return try? ShareLink.url(for: payload)
    }

    /// The QR's URL: the payload shrunk along `ShareQRBudget`'s policy until
    /// the encoder accepts it. Nil only for the no-name/no-identity gates.
    static func qrURL(
        scoreboard: Scoreboard, settings: Settings, identityStore: ShareIdentityStore,
        dailyStore: DailyStore
    ) -> URL? {
        let trimmed = settings.shareName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let identity = identityStore.identity() else { return nil }
        let issuedAt = Date()  // one stamp for every candidate: identical fit inputs
        return ShareQRBudget.firstFitting(
            scores: scores(from: scoreboard), career: settings.shareIncludeCareer
        ) { plan in
            guard
                let payload = try? identity.makePayload(
                    name: trimmed, scores: plan.scores,
                    career: plan.career ? career(from: scoreboard) : nil,
                    daily: dailyWindow(from: dailyStore, days: plan.dailyDays),
                    issuedAt: issuedAt),
                let url = try? ShareLink.url(for: payload),
                QRCode.ciImage(from: url.absoluteString) != nil
            else { return nil }
            return url
        }
    }
}
