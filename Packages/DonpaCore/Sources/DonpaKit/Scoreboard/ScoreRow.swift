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
                .frame(width: 56, alignment: .trailing)
            HStack(spacing: 3) {
                if recordMarker == .progress { newBestMarker }
                if let progress = scoreboard.bestProgress(for: config) {
                    // Floor, not round: a 99.7%-cleared loss must not read "100%".
                    Text("\(Int((progress * 100).rounded(.down)))%").font(.body.monospaced())
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, alignment: .trailing)
            HStack(spacing: 3) {
                if recordMarker == .time { newBestMarker }
                if let best = scoreboard.best(for: config) {
                    Text(TimeFormat.mmsst(centiseconds: best)).font(.body.monospaced().bold())
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, alignment: .trailing)
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
            if let onPlay { playButton(onPlay) }
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
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
