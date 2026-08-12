import DonpaCore
import SwiftUI

/// The timer readout, observing the `GameClock` ON ITS OWN so the ~10×/sec tick
/// re-renders only this little view — not the whole `GameContent` body (which the
/// surrounding views and the board scene would otherwise re-diff 10×/sec, a real
/// idle/battery cost, worst on iOS).
struct TimerReadout: View {
    @ObservedObject var clock: GameClock
    let tint: Color

    var body: some View {
        CounterReadout.time(centiseconds: clock.elapsedCentiseconds, tint: tint)
    }
}

/// A fixed-width LED-style readout with a leading glyph (⚑ / ⏱) — the mine count
/// and timer. Shrinks to fit narrow windows. The glyph is meaningless to
/// VoiceOver, so a real `a11y` label is spoken instead.
struct CounterReadout: View {
    let glyph: String
    let value: String
    let a11y: LocalizedStringKey
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: glyph).font(.title3)
            Text(verbatim: value)
                .font(.system(.title, design: .monospaced).weight(.bold))
                .foregroundStyle(tint)
        }
        .lineLimit(1)
        .layoutPriority(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(a11y, bundle: .module))
        .accessibilityValue(Text(verbatim: value))
    }

    /// Flag/mine count, fixed 3-digit (e.g. `010`).
    static func mines(_ value: Int, tint: Color) -> CounterReadout {
        CounterReadout(
            glyph: "⚑", value: String(format: "%03d", max(0, value)),
            a11y: "Mines remaining", tint: tint)
    }

    /// Whole-second timer. Each format runs to its full width before the next
    /// takes over — `000`…`999` (seconds), then `16:40`…`99:59` (`m:ss`), then
    /// `1:40:00`… (`h:mm:ss`) — so `999`→`16:40` and `99:59`→`1:40:00` follow the
    /// same rule. A marathon board keeps counting; recorded times were always
    /// exact regardless.
    static func time(centiseconds: Int, tint: Color) -> CounterReadout {
        let seconds = max(0, centiseconds / 100)
        let value: String
        if seconds < 1000 {
            value = String(format: "%03d", seconds)
        } else if seconds < 6000 {
            value = String(format: "%d:%02d", seconds / 60, seconds % 60)
        } else {
            value = String(
                format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return CounterReadout(glyph: "⏱", value: value, a11y: "Time, seconds", tint: tint)
    }
}

/// Live fraction of safe cells revealed, as a whole percent. Always shown so the
/// player can track progress on boards they rarely fully clear.
struct ProgressReadout: View {
    let progress: Double
    let tint: Color

    var body: some View {
        // Floor, matching the scoreboard's "Best %" (so 3.6% reads "3%").
        let pct = Int((progress * 100).rounded(.down))
        // Zero-pad to 3 digits so the width never jitters across 1→2→3 digits.
        return HStack(spacing: 4) {
            Image(systemName: "chart.bar.fill").font(.body)
            Text(verbatim: String(format: "%03d%%", pct))
                .font(.system(.title, design: .monospaced).weight(.bold))
                .foregroundStyle(tint)
        }
        .lineLimit(1)
        .layoutPriority(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Cleared", bundle: .module))
        .accessibilityValue(Text(verbatim: "\(pct)%"))
        .accessibilityIdentifier("game.progress")
    }
}
