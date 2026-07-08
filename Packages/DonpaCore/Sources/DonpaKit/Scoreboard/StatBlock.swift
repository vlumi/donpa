import DonpaCore
import SwiftUI

/// The figures a `StatBlock` renders, decoupled from where they come from — summed
/// across all configs for the global career, or read off one `ScoreRecord` for a
/// single config's expansion. Same shape at both scopes, so one component draws both.
struct StatFigures {
    var gamesPlayed = 0
    var wins = 0
    var tilesOpened = 0
    var flagsPlaced = 0
    var minesDisarmed = 0
    var minesHit = 0
    var chordsUsed = 0
    var noFlagWins = 0
    var noChordWins = 0
    var playtimeCentiseconds = 0
    var forcedGuesses = 0
    var guessesSurvived = 0
    /// Longest-odds forced guess survived (lower = luckier), or nil if none yet.
    var luckiestGuess: LuckiestGuess?
    /// Fastest winning times, fastest first (may be empty). Shown only in a single
    /// config's expansion — the global career has no meaningful "top times" list.
    var topTimes: [BestTime] = []
    var firstPlayed: Date?

    /// One config's figures, straight off its merged record.
    init(record: ScoreRecord) {
        gamesPlayed = record.gamesPlayed.total
        wins = record.wins.total
        tilesOpened = record.tilesOpened.total
        flagsPlaced = record.flagsPlaced.total
        minesDisarmed = record.minesDisarmed.total
        minesHit = record.minesHit.total
        chordsUsed = record.chordsUsed.total
        noFlagWins = record.noFlagWins.total
        noChordWins = record.noChordWins.total
        playtimeCentiseconds = record.playtimeCentiseconds.total
        forcedGuesses = record.forcedGuesses.total
        guessesSurvived = record.guessesSurvived.total
        luckiestGuess = record.luckiestGuess
        topTimes = record.topTimes
        firstPlayed = record.firstPlayed
    }

    /// The global career: sum every displayed config. No top-times list at this scope.
    init(career records: [ScoreRecord]) {
        for r in records {
            gamesPlayed += r.gamesPlayed.total
            wins += r.wins.total
            tilesOpened += r.tilesOpened.total
            flagsPlaced += r.flagsPlaced.total
            minesDisarmed += r.minesDisarmed.total
            minesHit += r.minesHit.total
            chordsUsed += r.chordsUsed.total
            noFlagWins += r.noFlagWins.total
            noChordWins += r.noChordWins.total
            playtimeCentiseconds += r.playtimeCentiseconds.total
            forcedGuesses += r.forcedGuesses.total
            guessesSurvived += r.guessesSurvived.total
            if let lucky = r.luckiestGuess {
                luckiestGuess = min(luckiestGuess ?? lucky, lucky)
            }
            if let f = r.firstPlayed { firstPlayed = min(firstPlayed ?? f, f) }
        }
    }

    var hasPlayed: Bool { gamesPlayed > 0 }
}

/// A labelled grid of one scope's figures (career or a single config), plus — for a
/// single config — its top times and a "playing since" line. The same block is used
/// for the global career and each config's inline expansion, so the two always read
/// alike. Lays out in one column when narrow, two when there's room.
struct StatBlock: View {
    let figures: StatFigures
    /// One hex config's stats use "cells" (FI kennot); false for square configs
    /// AND for the cross-family career, whose totals mix both shapes.
    var hexCells = false
    /// Two columns of stat pairs above this width, one below it.
    var twoColumnWidth: CGFloat = 360
    /// Horizontal inset matching the surrounding rows.
    var rowInset: CGFloat = 10
    /// Compact scale (smaller font + tighter rows) for the inline per-config
    /// expansion — a config's block is a long list nested inside a row, so it reads
    /// better a notch down. The global Career uses the full size.
    var compact: Bool = false

    private var valueFont: Font { compact ? .subheadline.monospaced() : .body.monospaced() }
    private var labelFont: Font { compact ? .subheadline : .body }
    private var rowVPad: CGFloat { compact ? 4 : 6 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statGrid
            if !figures.topTimes.isEmpty { bestTimes }
            if let since = figures.firstPlayed { playingSince(since) }
        }
    }

    /// The count rows. `ViewThatFits` picks the two-column arrangement when it fits
    /// the width, else stacks to one column — no GeometryReader needed.
    private var statGrid: some View {
        let pairs = statPairs
        return ViewThatFits(in: .horizontal) {
            twoColumn(pairs)
            oneColumn(pairs)
        }
    }

    private func oneColumn(_ pairs: [(LocalizedStringKey, String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { i, pair in
                statRow(pair.0, pair.1)
                if i != pairs.count - 1 { Divider() }
            }
        }
    }

    private func twoColumn(_ pairs: [(LocalizedStringKey, String)]) -> some View {
        // Split down the middle; left column gets the extra when odd.
        let half = (pairs.count + 1) / 2
        let left = Array(pairs.prefix(half))
        let right = Array(pairs.suffix(from: half))
        return HStack(alignment: .top, spacing: 28) {
            oneColumn(left).frame(maxWidth: .infinity)
            oneColumn(right).frame(maxWidth: .infinity)
        }
        // A firm floor so ViewThatFits only picks this when each column is roomy.
        .frame(minWidth: twoColumnWidth)
    }

    /// Label/value pairs, in display order.
    private var statPairs: [(LocalizedStringKey, String)] {
        var pairs: [(LocalizedStringKey, String)] = [
            ("Games played", grouped(figures.gamesPlayed)),
            ("Wins", grouped(figures.wins)),
            ("No-flag wins", grouped(figures.noFlagWins)),
            ("No-chord wins", grouped(figures.noChordWins)),
            // Opening actions grouped (tiles + chords, which clear tiles), then the
            // flag/mine cluster, then playtime.
            (hexCells ? "Cells cleared" : "Tiles cleared", grouped(figures.tilesOpened)),
            ("Chords used", grouped(figures.chordsUsed)),
            ("Flags placed", grouped(figures.flagsPlaced)),
            ("Mines disarmed", grouped(figures.minesDisarmed)),
            ("Mines hit", grouped(figures.minesHit)),
            ("Time played", ScoreboardView.durationLabel(figures.playtimeCentiseconds)),
        ]
        // The luck line — only once the board has actually forced a guess (a row
        // of "0/0" would just be noise), and the record only with it.
        if figures.forcedGuesses > 0 {
            let ratio = Double(figures.guessesSurvived) / Double(figures.forcedGuesses)
            pairs.append(
                (
                    "Lucky guesses",
                    "\(grouped(figures.guessesSurvived))/\(grouped(figures.forcedGuesses))"
                        + " (\(Self.percent(ratio)))"
                ))
            if let lucky = figures.luckiestGuess {
                pairs.append(("Luckiest guess", Self.percent(lucky.survival)))
            }
        }
        return pairs
    }

    /// A whole-number locale percentage ("33 %" in FI, "33%" in EN).
    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    private func statRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label, bundle: .module).font(labelFont)
            Spacer(minLength: 12)
            Text(verbatim: value).font(valueFont)
        }
        .padding(.vertical, rowVPad)
        .padding(.horizontal, rowInset)
    }

    /// The config's fastest winning times, each with a relative locale date
    /// ("2 days ago"), not an absolute one — a recency cue, not a log entry.
    private var bestTimes: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Best times", bundle: .module)
                .font(.caption.bold()).foregroundStyle(.secondary)
                .padding(.horizontal, rowInset)
            ForEach(Array(figures.topTimes.enumerated()), id: \.offset) { i, t in
                HStack {
                    Text(verbatim: "\(i + 1).").foregroundStyle(.secondary)
                        .frame(width: 22, alignment: .leading)
                    Text(TimeFormat.mmsst(centiseconds: t.centiseconds))
                        .font(.body.monospaced().bold())
                    Spacer(minLength: 12)
                    Text(verbatim: Self.relative(t.achievedAt))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
                .padding(.horizontal, rowInset)
            }
        }
    }

    private func playingSince(_ date: Date) -> some View {
        Text("Playing since \(Self.medium(date))", bundle: .module)
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, rowInset)
    }

    private func grouped(_ value: Int) -> String { ScoreboardView.grouped(value) }

    /// "2 days ago" in the current locale — the OS relative formatter.
    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }

    /// A plain medium locale date for "Playing since" ("Jul 1, 2026").
    static func medium(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}
