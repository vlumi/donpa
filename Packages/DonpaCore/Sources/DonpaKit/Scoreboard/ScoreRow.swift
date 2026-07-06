import DonpaCore
import SwiftUI

/// One config's row in the high-score table: name/insignia, clears, best %, best
/// time — plus the two row cues (the just-set record flourish and the persistent
/// "you are here" band for the config being played) and the non-colour "new best"
/// marker on the value that just improved.
struct ScoreRow: View {
    @ObservedObject var scoreboard: Scoreboard
    let config: GameConfig
    /// The config the player is currently on, for the "you are here" band.
    let currentConfigKey: String?
    /// Shared horizontal inset (matches the header + section padding).
    let rowInset: CGFloat
    /// Whether this row's stat-block expansion is open (accordion — one at a time).
    var isExpanded: Bool = false
    /// Toggle the expansion. When nil the row isn't expandable (kept for callers
    /// that just want a static row).
    var onToggle: (() -> Void)?
    /// Start a fresh game on this row's config (the expansion's "New game" button).
    var onPlay: (() -> Void)?
    /// The tracked friends to compare against (already filtered to the chosen group),
    /// and your display name. Empty / nil → no comparison shown (rows still work).
    var rivals: [Friend] = []
    var yourName: String = ""

    /// You + rivals ranked by best time on this config — nil when there are no rivals,
    /// so rows behave exactly as before when the friends list is empty.
    private var ranking: ScoreComparison.Ranking? {
        guard !rivals.isEmpty else { return nil }
        return RivalRanking.ranking(
            config: config, scoreboard: scoreboard, rivals: rivals, yourName: yourName)
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryRow
            if isExpanded { expansion }
        }
        .background(rowHighlight)
    }

    // A tap gesture (not a Button) so a scroll that STARTS on a row doesn't toggle
    // it — inside a ScrollView a plain Button fires even when the touch turns into a
    // drag, which made the last row nearly impossible to open. A tap only fires when
    // the finger doesn't move past the scroll threshold.
    private var summaryRow: some View {
        HStack {
            // Grid/Hive rows: rank insignia in a fixed-width column (so size
            // letters line up), then the size name. No edges tag — the list is
            // already scoped to one edges value by the filter, so every row shares
            // it. Basic rows show their preset name.
            // Shrink to fit rather than truncate or force the row wider — a long
            // preset name ("Intermediate") scales down instead of clipping or
            // wobbling the sheet width when the family filter changes.
            if let size = config.size, let density = config.density {
                DensityInsignia.image(density)
                    .resizable().scaledToFit().frame(width: 30, height: 20)
                Text(verbatim: size.label).lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Text(verbatim: config.label).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer()
            Text(verbatim: ScoreboardView.grouped(scoreboard.wins(for: config)))
                .font(.body.monospaced())
                .numericCell()
                .frame(width: ScoreColumns.cleared, alignment: .trailing)
            HStack(spacing: 3) {
                if recordMarker == .progress { newBestMarker }
                if let progress = scoreboard.bestProgress(for: config) {
                    // Floor, not round: a 99.7%-cleared loss must not read "100%".
                    Text("\(Int((progress * 100).rounded(.down)))%").font(.body.monospaced())
                        .numericCell()
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .frame(width: ScoreColumns.bestProgress, alignment: .trailing)
            HStack(spacing: 3) {
                if let rank = ranking?.yourRank { rankBadge(rank) }
                if recordMarker == .time { newBestMarker }
                if let best = scoreboard.best(for: config) {
                    Text(TimeFormat.mmsst(centiseconds: best)).font(.body.monospaced().bold())
                        .numericCell()
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .frame(width: ScoreColumns.bestTime, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 10)
        .padding(.horizontal, rowInset)
        .onTapGesture { onToggle?() }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(isExpanded ? "Hide details" : "Show details", bundle: .module))
    }

    /// This config's own stats — the same `StatBlock` the global career uses, scoped
    /// to one record. An unplayed config shows a gentle placeholder instead.
    @ViewBuilder private var expansion: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let record = scoreboard.record(for: config) {
                StatBlock(figures: StatFigures(record: record), rowInset: rowInset, compact: true)
            } else {
                Text("No games on this board yet.", bundle: .module)
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, rowInset)
            }
            if let ranking { leaderboard(ranking) }
            if let onPlay { playButton(onPlay) }
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The mixed top-5 leaderboard for this board — you slotted among rivals by time,
    /// highlighted in place. If you're outside the top 5, your own row is appended
    /// below a break so you can still see where you stand.
    @ViewBuilder private func leaderboard(_ ranking: ScoreComparison.Ranking) -> some View {
        let top = Array(ranking.entries.prefix(5))
        let youInTop = top.contains { $0.isYou }
        VStack(alignment: .leading, spacing: 4) {
            Text("Leaderboard", bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(top.enumerated()), id: \.offset) { index, entry in
                leaderboardRow(place: index + 1, entry: entry)
            }
            // You didn't make the top 5 → show your line below, after a break.
            if !youInTop, let you = ranking.entries.first(where: { $0.isYou }),
                let rank = ranking.yourRank
            {
                Text("⋯").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                leaderboardRow(place: rank, entry: you)
            }
        }
        .padding(.horizontal, rowInset)
    }

    private func leaderboardRow(place: Int, entry: ScoreComparison.Entry) -> some View {
        HStack(spacing: 8) {
            Text("\(place)").font(.caption.monospaced())
                .foregroundStyle(.secondary).frame(width: 20, alignment: .trailing)
            Text(entry.name).lineLimit(1).minimumScaleFactor(0.7)
                .fontWeight(entry.isYou ? .bold : .regular)
            Spacer()
            if let best = entry.best {
                Text(TimeFormat.mmsst(centiseconds: best)).font(.body.monospaced()).numericCell()
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        // Highlight your own line so it stands out in the mix.
        .background(entry.isYou ? Color.accentColor.opacity(0.12) : .clear)
    }

    /// The tiny standing badge for the collapsed row: a medal for 1–3, a compact "4+"
    /// beyond — kept minimal to fit SE portrait alongside the existing columns.
    @ViewBuilder private func rankBadge(_ rank: Int) -> some View {
        switch rank {
        case 1: badgeGlyph("1.circle.fill", .yellow)
        case 2: badgeGlyph("2.circle.fill", .gray)
        case 3: badgeGlyph("3.circle.fill", .brown)
        default:
            Text("4+").font(.caption2.bold()).foregroundStyle(.secondary)
                .accessibilityLabel(Text("rank \(rank)", bundle: .module))
        }
    }

    private func badgeGlyph(_ systemName: String, _ tint: Color) -> some View {
        Image(systemName: systemName).font(.caption).foregroundStyle(tint)
            .accessibilityLabel(Text("rank \(String(systemName.prefix(1)))", bundle: .module))
    }

    /// Jump straight into a fresh game on this board — closes the loop between
    /// "check my best here" and "try to beat it".
    private func playButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text("New game on this board", bundle: .module)
            } icon: {
                Image(systemName: "play.fill")
            }
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .foregroundStyle(.white)
            .background(Color.accentColor, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, rowInset)
        .accessibilityIdentifier("scoreboard.play")
    }

    /// Which "Best" column, if any, just set a record on this row — so the non-color
    /// "new best" marker can flag the exact value that improved (color alone isn't
    /// relied on; the row band is the primary cue). Derived from the stored best: a
    /// recorded time means the PB was a win (time); progress-only means a loss
    /// (clear-%). nil unless this is the recent-record row.
    private enum RecordField { case time, progress }
    private var recordMarker: RecordField? {
        guard scoreboard.recentRecord == config.storageKey else { return nil }
        return scoreboard.best(for: config) != nil ? .time : .progress
    }

    /// A small upward chevron flagging the just-improved value. Shape, not colour,
    /// so it survives any user accent choice and is colour-blind safe.
    private var newBestMarker: some View {
        Image(systemName: "arrow.up")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("new best", bundle: .module))
    }

    /// Two distinct row cues. The just-set RECORD gets the strong accent flourish
    /// (transient — cleared when the next game ends). The CURRENT config (the board
    /// you're on) gets a subtler persistent "you are here" band, so opening the
    /// scoreboard always shows where you stand. Record wins when a row is both.
    @ViewBuilder private var rowHighlight: some View {
        if scoreboard.recentRecord == config.storageKey {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.5)))
        } else if currentConfigKey == config.storageKey {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.18), lineWidth: 1))
        }
    }
}
