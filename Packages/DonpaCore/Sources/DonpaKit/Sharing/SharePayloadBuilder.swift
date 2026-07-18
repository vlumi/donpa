import DonpaCore
import Foundation

/// Assembles a signed `SharePayload` from the scoreboard's MERGED cross-device
/// view (`displayRecords`), so a share reflects your true best, not just this
/// device's. `issuedAt` is the replay/downgrade guard.
@MainActor
enum SharePayloadBuilder {
    static func build(
        from scoreboard: Scoreboard, identity: ShareIdentity, name: String,
        includeCareer: Bool, daily: [SharedDailyDay]? = nil, maxScores: Int? = nil, now: Date
    ) -> SharePayload? {
        var scores: [SharedConfigScore] = scoreboard.displayRecords.map { key, rec in
            SharedConfigScore(
                key: key,
                best: rec.best?.centiseconds,
                wins: rec.wins.total,
                bestProgress: rec.bestLossProgress,
                recentPace: Pace.medianPace(of: rec.recentWins),
                bestPace: rec.bestPace?.pace)
        }
        // A QR has a hard byte ceiling (a veteran's every-config payload
        // overflows it and the encoder yields nothing) — under a budget, keep
        // the boards a rival cares about most: won configs, most wins first.
        if let maxScores, scores.count > maxScores {
            scores =
                scores
                .sorted { ($0.wins, $1.key) > ($1.wins, $0.key) }
                .prefix(maxScores)
                .map { $0 }
        }
        scores.sort { $0.key < $1.key }  // stable order → deterministic payload/QR

        let career = includeCareer ? Self.career(from: scoreboard) : nil
        return try? identity.makePayload(
            name: name, scores: scores, career: career, daily: daily, issuedAt: now)
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
        dailyStore: DailyStore, dailyDays: Int?, maxScores: Int? = nil
    ) -> URL? {
        if scoreboard.isCloudActive { scoreboard.refreshFromCloud() }
        let trimmed = settings.shareName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            let identity = identityStore.identity(),
            let payload = build(
                from: scoreboard, identity: identity, name: trimmed,
                includeCareer: settings.shareIncludeCareer,
                daily: dailyWindow(from: dailyStore, days: dailyDays),
                maxScores: maxScores, now: Date())
        else { return nil }
        return try? ShareLink.url(for: payload)
    }
}
