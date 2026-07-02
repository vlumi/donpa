import DonpaCore
import SwiftUI

/// The new-game config chooser as a modal overlay: a dimmed backdrop (tap to
/// dismiss) over a card holding `BoardSelectionPicker`, a Start button, and a
/// close (X). The single place a new game is configured. An overlay rather than a
/// `.sheet` so the dismiss affordances match the result screen across platforms.
/// On macOS it's keyboard-drivable: arrows move/cycle, Return starts, Esc closes.
struct NewGamePopup: View {
    @ObservedObject var settings: Settings
    /// Begin a game with the current selection.
    let onStart: () -> Void
    /// Dismiss without starting (X, backdrop tap, or Escape).
    let onClose: () -> Void

    #if os(macOS)
    /// Keyboard-focused picker row (0 = Mode). nil until the first arrow press.
    @State private var focusedRow: Int?
    #endif

    /// Measured natural height of the scrollable content, so the card hugs it
    /// until it would exceed the available height (then the ScrollView scrolls).
    @State private var contentHeight: CGFloat = 0

    /// Preferred card width, FIXED across all family pages so paging never resizes
    /// the frame — a family-dependent width left the pager half-resized when
    /// returning to a narrower page. Roomy enough that every chip row and the
    /// preset cards breathe.
    private static let idealWidth: CGFloat = 680

    /// The card chrome above the scroll region: the "New game" title line plus the
    /// VStack spacing under it. Subtracted from the window height so the scroll
    /// area's cap leaves room for the title (and its own padding), rather than the
    /// card growing past the window and hiding the Start button at the bottom.
    private static let titleChromeHeight: CGFloat = 50

    /// At/above this available width the modal uses the wide sidebar+detail layout;
    /// below it (portrait phone), the vertical swipe-pager. Chosen so the
    /// sidebar+detail's one-row size chips fit — any landscape phone clears it, a
    /// portrait phone doesn't. (A small landscape phone that just clears it wraps
    /// the size chips 4+3 via ViewThatFits — graceful, not broken.)
    private static let sidebarMinWidth: CGFloat = 600

    /// Layout chosen by the actual viewport SHAPE, not the platform or size class:
    /// only a narrow (portrait-phone) viewport gets the pager; everything wider is
    /// the sidebar. Runtime — no `#if os`.
    private static func layout(for viewport: CGSize) -> BoardSelectionPicker.Layout {
        viewport.width >= sidebarMinWidth ? .sidebar : .pager
    }

    /// Card width: the ideal, but never wider than the window allows (`available`
    /// is already the window minus the outer padding). On a small window it shrinks
    /// to fit — the chip rows wrap and the content flexes — so nothing spills past
    /// the card edge. Floored so it can't collapse to nothing during a resize.
    private static func cardWidth(available: CGFloat) -> CGFloat {
        min(Self.idealWidth, max(0, available))
    }

    var body: some View {
        ZStack {
            // Dimmed backdrop: blocks what's behind and dismisses when tapped.
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }

            // The card keeps one fixed design width (clamped to the window), and
            // caps height so a short window scrolls rather than clipping. On a
            // roomy screen everything is visible without scrolling.
            GeometryReader { geo in
                card(
                    layout: Self.layout(for: geo.size),
                    width: Self.cardWidth(available: geo.size.width - 48),
                    // Height budget for the SCROLLABLE region only — subtract the
                    // card's own chrome (outer padding 48 + card padding 48 + the
                    // title row and its spacing) so the scroll area caps at what's
                    // actually left. Capping at the full window height instead let
                    // the card grow taller than the window, pushing the last scroll
                    // item (the Start button) off the bottom where the scroll,
                    // already at its cap, couldn't reveal it.
                    maxHeight: geo.size.height - 48 - 48 - Self.titleChromeHeight
                )
                .animation(.snappy, value: settings.family)
                .overlay(alignment: .topTrailing) { closeButton }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            }
        }
        #if os(macOS)
        // AppKit key-catcher: @FocusState can't reliably take first responder from
        // the SpriteKit board, especially after a game ends.
        .background(KeyCatcher { handleKey($0) })
        #endif
    }

    #if os(macOS)
    private func handleKey(_ key: KeyCatcher.Key) {
        switch key {
        case .up: focusedRow = max(0, (focusedRow ?? 0) - 1)
        case .down:
            // grid/hive: family, density, size, edges
            let rows = settings.family == .basic ? 2 : 4
            focusedRow = min(rows - 1, (focusedRow ?? -1) + 1)
        case .left: cycleSelection(in: focusedRow ?? 0, by: -1)
        case .right: cycleSelection(in: focusedRow ?? 0, by: 1)
        case .enter: onStart()
        case .escape: onClose()
        }
    }
    #endif

    /// The card grows to `width` (so every option is visible side-by-side when
    /// there's room) and hugs its content height up to `maxHeight`; past that the
    /// content scrolls with the title pinned, so the selectors stay reachable.
    private func card(layout: BoardSelectionPicker.Layout, width: CGFloat, maxHeight: CGFloat)
        -> some View
    {
        VStack(spacing: 20) {
            Text("New game", bundle: .module).font(.title2.bold())

            // The picker scrolls if it's ever taller than the space; the pager
            // layout's Start is pinned BELOW this scroll (outside it) so it can't
            // be clipped, while the sidebar layout carries its own Start inside its
            // pinned column.
            scrollableContent(layout: layout)
                // Hug content until it would overflow; only then cap + scroll.
                .frame(height: min(contentHeight, max(0, maxHeight)))
                .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }

            if layout == .pager {
                picker(layout: layout).startButton
            }
        }
        .padding(24)
        .frame(width: width)
        // Clip to the rounded card so nothing a child lays out wider (a chip row
        // or the pager mid-measure on a very narrow window) can spill past the card
        // edge — and, since the card is already clamped to the window, off-screen.
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 6)
    }

    /// The `BoardSelectionPicker` for a layout, configured once so the scroll body
    /// and the pinned Start button share the same instance settings.
    private func picker(layout: BoardSelectionPicker.Layout) -> BoardSelectionPicker {
        #if os(macOS)
        BoardSelectionPicker(
            settings: settings, focusedRow: focusedRow,
            onFocusRow: { focusedRow = $0 }, layout: layout, onStart: onStart)
        #else
        BoardSelectionPicker(settings: settings, layout: layout, onStart: onStart)
        #endif
    }

    /// The picker in a ScrollView (engages only when the card hits its height cap;
    /// suppresses rubber-banding when it doesn't, where available). Start lives
    /// OUTSIDE this — in the picker's own sidebar column (sidebar layout) or pinned
    /// below by `card` (pager layout) — so it's never clipped by the scroll.
    @ViewBuilder private func scrollableContent(layout: BoardSelectionPicker.Layout) -> some View {
        let scroll = ScrollView {
            VStack(spacing: 20) {
                picker(layout: layout)
                #if os(macOS)
                Text("Arrows to choose · Return to start", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #endif
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                })
        }
        if #available(iOS 16.4, macOS 13.3, *) {
            scroll.scrollBounceBehavior(.basedOnSize)
        } else {
            scroll
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark.circle.fill")
                .font(.title)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.4))
                .padding(8)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)  // Escape closes
        .accessibilityLabel(Text("Close", bundle: .module))
    }

    #if os(macOS)
    /// Cycle the selection in the given row. Row 0 is Family; rows 1+ are the
    /// preset (Basic), or Density / Size / Edges (Grid/Hive).
    private func cycleSelection(in row: Int, by step: Int) {
        switch (settings.family, row) {
        case (_, 0):
            settings.family = Self.stepped(settings.family, by: step)
        case (.basic, _):
            settings.basicPreset = Self.stepped(settings.basicPreset, by: step)
        case (.grid, 1), (.hive, 1):
            let path = Settings.densityPath(settings.family)
            settings[keyPath: path] = Self.stepped(settings[keyPath: path], by: step)
        case (.grid, 2), (.hive, 2):
            let path = Settings.sizePath(settings.family)
            settings[keyPath: path] = Self.stepped(settings[keyPath: path], by: step)
        case (.grid, _), (.hive, _):  // row 3: edges
            let path = Settings.edgesPath(settings.family)
            settings[keyPath: path] = Self.stepped(settings[keyPath: path], by: step)
        }
    }

    /// Next/previous case of a `CaseIterable` enum, clamped at the ends (no
    /// wrap), matching the chip rows.
    private static func stepped<T: CaseIterable & Equatable>(_ value: T, by step: Int) -> T {
        let all = Array(T.allCases)
        guard let i = all.firstIndex(of: value), !all.isEmpty else { return value }
        let next = min(max(i + step, 0), all.count - 1)
        return all[next]
    }
    #endif
}

/// Carries the scrollable content's natural height up to the card.
private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
