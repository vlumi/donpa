import DonpaCore
import SwiftUI

/// One config's row in the high-score table: name/insignia and the score
/// columns, expandable to the config's stat-block.
struct ScoreRow: View {
    @ObservedObject var scoreboard: Scoreboard
    let config: GameConfig
    let currentConfigKey: String?
    let rowInset: CGFloat
    var isExpanded: Bool = false
    var isKeyFocused: Bool = false
    var onToggle: (() -> Void)?
    var onPlay: (() -> Void)?
    var rivals: [Friend] = []
    var yourName: String = ""
    /// The Record's per-open attribution index (nil = no glyphs).
    var attribution: DeviceAttribution?

    /// Grows the stat columns with Dynamic Type — fixed widths would shrink
    /// grown values back down via `numericCell`, defeating the enlargement.
    /// Must match `ScoreboardView.columnScale` so the table stays aligned.
    @ScaledMetric(relativeTo: .body) private var columnScale: CGFloat = 1

    /// nil when there are no rivals, so rows behave exactly as before.
    private var ranking: ScoreComparison.Ranking? {
        guard !rivals.isEmpty else { return nil }
        return FriendRanking.ranking(
            config: config, scoreboard: scoreboard, rivals: rivals, yourName: yourName)
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryRow
            if isExpanded { expansion }
        }
        .background(rowHighlight)
        .modifier(FocusRing(focused: isKeyFocused, inset: 0))
    }

    // A tap gesture, not a Button: inside a ScrollView a Button fires even when
    // the touch turns into a drag, which made the last row nearly impossible to
    // open without toggling it.
    private var summaryRow: some View {
        HStack {
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
                .frame(width: ScoreColumns.cleared * columnScale, alignment: .trailing)
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
            .frame(width: ScoreColumns.bestProgress * columnScale, alignment: .trailing)
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
            .frame(width: ScoreColumns.bestTime * columnScale, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, rowInset)
        // Shape AFTER the padding so the whole padded row is tappable — the
        // difference between a 20pt and a 44pt tap target.
        .contentShape(Rectangle())
        .onTapGesture { onToggle?() }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(isExpanded ? "Hide details" : "Show details", bundle: .module))
    }

    @ViewBuilder private var expansion: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let record = scoreboard.record(for: config) {
                StatBlock(
                    figures: StatFigures(record: record), hexCells: config.isHex,
                    rowInset: rowInset, compact: true,
                    deviceClass: attribution.map { index in
                        { index.deviceClass(for: $0, config: config.storageKey) }
                    })
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

    /// Top-5 by time, you slotted in place; outside the top 5 your row is
    /// appended below a break so you can still see where you stand.
    @ViewBuilder private func leaderboard(_ ranking: ScoreComparison.Ranking) -> some View {
        let top = Array(ranking.entries.prefix(5))
        let youInTop = top.contains { $0.isYou }
        VStack(alignment: .leading, spacing: 4) {
            Text("Leaderboard", bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(top.enumerated()), id: \.offset) { index, entry in
                leaderboardRow(place: index + 1, entry: entry)
            }
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
            PaceText(pace: entry.bestPace)
            if let best = entry.best {
                Text(TimeFormat.mmsst(centiseconds: best)).font(.body.monospaced()).numericCell()
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .background(entry.isYou ? Color.accentColor.opacity(0.12) : .clear)
    }

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
        // Palette mode, black numeral ON the tint circle: the plain tinted glyph
        // knocked the numeral out to the background and sat near 1.5:1 contrast.
        Image(systemName: systemName).font(.caption)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.black, tint)
            .accessibilityLabel(Text("rank \(String(systemName.prefix(1)))", bundle: .module))
    }

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

    /// Which "Best" column just set a record, for the non-color marker. Derived
    /// from the stored best: a recorded time means the PB was a win (time);
    /// progress-only means a loss (clear-%).
    private enum RecordField { case time, progress }
    private var recordMarker: RecordField? {
        guard scoreboard.recentRecord == config.storageKey else { return nil }
        return scoreboard.best(for: config) != nil ? .time : .progress
    }

    /// Shape, not colour — survives any accent choice and is colour-blind safe.
    private var newBestMarker: some View {
        Image(systemName: "arrow.up")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("new best", bundle: .module))
    }

    /// The just-set record gets the transient accent flourish; the config being
    /// played gets a subtler persistent band. Record wins when a row is both.
    @ViewBuilder private var rowHighlight: some View {
        if scoreboard.recentRecord == config.storageKey {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.5)))
        } else if currentConfigKey == config.storageKey {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.30), lineWidth: 1))
        }
    }
}
