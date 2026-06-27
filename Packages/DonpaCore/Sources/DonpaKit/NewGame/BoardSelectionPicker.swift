import DonpaCore
import SwiftUI

/// The board-config chooser: a Classic/Modern mode switch over the matching
/// picker (3 classic presets, or Size × Density for Modern). Binds directly to
/// `Settings` with no side effects — picking here updates the *pending* choice;
/// the host decides when to actually start a game (the home hub's Start button).
///
/// The difficulty/size rows are `CarouselPicker` drums (name-only cards under a
/// fixed center window), with a detail line below the selected card showing its
/// facts (dimensions / mine %) and a short flavor tagline. The drum replaced a
/// segmented control, whose labels truncated once a row had many or long options
/// (Size's 7 tiers, "Intermediate"). Mode stays a segmented control — two short
/// options fit fine.
///
/// On macOS it's keyboard-drivable: up/down move between rows (Mode / Size /
/// Difficulty), left/right cycle the selection within the focused row. The
/// focused row is highlighted. `focusedRow` is owned by the host (the popup,
/// which holds the keyboard focus) and clamped here as the row set changes
/// (Classic has 2 rows, Modern 3). Cycling mutates `Settings`, and each carousel
/// follows its bound value, so the keys drive the drums without extra wiring.
struct BoardSelectionPicker: View {
    @ObservedObject var settings: Settings
    /// Index of the keyboard-focused row, or nil when not keyboard-driven (iOS,
    /// or before the first arrow press). Highlighted when set.
    var focusedRow: Int?
    /// Ask the host to move keyboard focus to a row — so clicking a control on
    /// macOS focuses that row, and the arrow keys then act on it. nil on iOS (no
    /// keyboard focus there).
    var onFocusRow: ((Int) -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            // Row 0: Mode — a plain segmented control (two short options fit).
            Picker("Mode", selection: $settings.mode) {
                ForEach(GameMode.allCases) { Text(verbatim: $0.label).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .modifier(FocusRing(focused: focusedRow == 0))
            // Changing the mode (a click on the segmented control) focuses row 0.
            .onChange(of: settings.mode) { _ in onFocusRow?(0) }

            switch settings.mode {
            case .classic:
                // Difficulty (row 1) lines up with Modern's difficulty row across
                // the mode switch.
                carouselRow(
                    1,
                    labels: ClassicPreset.allCases.map(\.label),
                    index: classicIndex,
                    detail: settings.classicPreset.detail,
                    tagline: settings.classicPreset.tagline)
            case .modern:
                carouselRow(
                    1,
                    labels: Density.allCases.map(\.label),
                    index: densityIndex,
                    detail: settings.modernDensity.detail,
                    tagline: settings.modernDensity.tagline,
                    // Rank insignia above each label, matching the status-bar patch.
                    symbol: { i in
                        let all = Density.allCases
                        return all.indices.contains(i) ? DensityInsignia.markImage(all[i]) : nil
                    })
                carouselRow(
                    2,
                    labels: BoardSize.allCases.map(\.label),
                    index: sizeIndex,
                    detail: settings.modernSize.detail,
                    tagline: settings.modernSize.tagline)
            }
        }
    }

    /// A carousel drum plus the detail/tagline line for its selected card.
    private func carouselRow(
        _ row: Int, labels: [String], index: Binding<Int>, detail: String, tagline: String,
        symbol: ((Int) -> Image?)? = nil
    ) -> some View {
        VStack(spacing: 4) {
            CarouselPicker(
                labels: labels, selection: index, focused: focusedRow == row, symbol: symbol,
                onInteract: { onFocusRow?(row) }
            )
            // Give each label set its own identity, so switching mode (which
            // swaps a row's options) builds a FRESH carousel that centers on
            // its current selection — rather than reusing the old scroll view
            // with a stale offset (ring/value/detail would disagree).
            .id(labels)
            HStack(spacing: 6) {
                Text(verbatim: detail).fontWeight(.bold).foregroundStyle(.primary)
                Text(verbatim: "·").foregroundStyle(.secondary)
                Text(verbatim: tagline).italic().foregroundStyle(.primary.opacity(0.75))
            }
            .font(.body)
            // Wrap rather than shrink — so a longer line (e.g. the difficulty
            // detail) keeps the SAME font size as a shorter one (the size detail),
            // instead of scaling down to fit one line.
            .lineLimit(2)
            .multilineTextAlignment(.center)
            // The line content swaps as the selection scrolls by — keep it from
            // reflowing the layout while the drum animates.
            .frame(maxWidth: .infinity)
            .animation(.snappy, value: detail)
        }
    }

    // MARK: Enum ↔ index bindings (the carousel works in index space)

    private var classicIndex: Binding<Int> {
        enumIndex(\.classicPreset, all: ClassicPreset.allCases)
    }
    private var densityIndex: Binding<Int> {
        enumIndex(\.modernDensity, all: Density.allCases)
    }
    private var sizeIndex: Binding<Int> {
        enumIndex(\.modernSize, all: BoardSize.allCases)
    }

    /// A `Binding<Int>` over a `Settings` enum property, mapping case↔offset in
    /// `allCases` so the carousel can drive it. Out-of-range writes are clamped.
    private func enumIndex<T: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<Settings, T>, all: [T]
    ) -> Binding<Int> {
        Binding(
            get: { all.firstIndex(of: settings[keyPath: keyPath]) ?? 0 },
            set: { i in
                guard all.indices.contains(i) else { return }
                settings[keyPath: keyPath] = all[i]
            })
    }
}

/// Wraps a control with the keyboard focus ring used across the picker rows.
private struct FocusRing: ViewModifier {
    let focused: Bool
    func body(content: Content) -> some View {
        content
            // Same always-present panel as the carousel rows, recoloured on focus
            // (never resizes), so the focused row reads consistently and the layout
            // doesn't wobble as keyboard focus moves.
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(focused ? 0.12 : 0))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.accentColor.opacity(focused ? 1 : 0), lineWidth: 2)))
    }
}
