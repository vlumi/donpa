import DonpaCore
import Foundation

/// Assembles a signed `SharePayload` from the scoreboard's MERGED cross-device
/// view (`displayRecords`), so a share reflects your true best, not just this
/// device's. `issuedAt` is the replay/downgrade guard.
@MainActor
enum SharePayloadBuilder {
    static func build(
        from scoreboard: Scoreboard, identity: ShareIdentity, name: String,
        includeCareer: Bool, now: Date
    ) -> SharePayload? {
        let scores: [SharedConfigScore] = scoreboard.displayRecords.map { key, rec in
            SharedConfigScore(
                key: key,
                best: rec.best?.centiseconds,
                wins: rec.wins.total,
                bestProgress: rec.bestLossProgress,
                recentPace: Pace.medianPace(of: rec.recentWins),
                bestPace: rec.bestPace?.pace)
        }
        .sorted { $0.key < $1.key }  // stable order → deterministic payload/QR

        let career = includeCareer ? Self.career(from: scoreboard) : nil
        return try? identity.makePayload(
            name: name, scores: scores, career: career, issuedAt: now)
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
    static func currentURL(
        scoreboard: Scoreboard, settings: Settings, identityStore: ShareIdentityStore
    ) -> URL? {
        if scoreboard.isCloudActive { scoreboard.refreshFromCloud() }
        let trimmed = settings.shareName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            let identity = identityStore.identity(),
            let payload = build(
                from: scoreboard, identity: identity, name: trimmed,
                includeCareer: settings.shareIncludeCareer, now: Date())
        else { return nil }
        return try? ShareLink.url(for: payload)
    }
}
