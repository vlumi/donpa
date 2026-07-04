import DonpaCore
import Foundation

/// Assembles a signed `SharePayload` from the scoreboard's MERGED (cross-device)
/// view — `displayRecords`, which is the G-counter-summed / best-time-min
/// projection across all your devices. So a share always reflects your true best,
/// not just this device's (see the score-sharing design note). The share flow is
/// responsible for refreshing-from-cloud first when sync is active, and for
/// labelling "this device only" honestly when it isn't.
@MainActor
enum SharePayloadBuilder {
    /// Build a payload for `name`, optionally including career totals, signed by
    /// `identity`. `now` is the `issuedAt` stamp (the replay/downgrade guard).
    /// Returns nil only if signing fails (shouldn't, with a valid identity).
    static func build(
        from scoreboard: Scoreboard, identity: ShareIdentity, name: String,
        includeCareer: Bool, now: Date
    ) -> SharePayload? {
        // Per-config bests + wins, straight off the merged records. Only configs with
        // an actual record ship (an untouched config isn't worth a payload slot).
        let scores: [SharedConfigScore] = scoreboard.displayRecords.map { key, rec in
            SharedConfigScore(
                key: key,
                best: rec.best?.centiseconds,
                wins: rec.wins.total,
                bestProgress: rec.bestLossProgress)
        }
        .sorted { $0.key < $1.key }  // stable order → deterministic payload/QR

        let career = includeCareer ? Self.career(from: scoreboard) : nil
        return try? identity.makePayload(
            name: name, scores: scores, career: career, issuedAt: now)
    }

    /// Career totals summed across every merged config record — mirrors the
    /// `StatFigures(career:)` scope used by the scoreboard's own career block.
    private static func career(from scoreboard: Scoreboard) -> SharedCareer {
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
