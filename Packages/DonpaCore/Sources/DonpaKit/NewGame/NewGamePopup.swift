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

    /// Preferred card width, FIXED across all family pages so paging never resizes
    /// the frame — a family-dependent width left the pager half-resized when
    /// returning to a narrower page. Roomy enough that every chip row and the
    /// preset cards breathe.
    private static let idealWidth: CGFloat = 680

    /// Top/bottom gap between the card and the window edge. Small, so on a short
    /// screen the card can grow nearly full-height (and Start rides up).
    private static let outerVMargin: CGFloat = 12

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
                // Centre with symmetric spacers rather than a `.frame(maxHeight:)`
                // alignment: a card whose subtree uses `.fixedSize(vertical:)` (the
                // sidebar layout) reports an ideal height that an aligning frame
                // top-anchors instead of centring. Equal-weight spacers always split
                // the slack evenly, so both layouts sit dead-centre on any viewport.
                card(
                    layout: Self.layout(for: geo.size),
                    width: Self.cardWidth(available: geo.size.width - 48)
                )
                // Close button in the CARD's corner — the overlay is on the card
                // (its actual `width`), so it sits at the card's top-right, not
                // the screen's.
                .overlay(alignment: .topTrailing) { closeButton }
                // Centre in the full slot. A `.frame(alignment: .center)` centres the
                // card whether it's SHORTER than the slot (margin all round) or TALLER
                // (e.g. the sidebar on a short landscape phone) — in which case it
                // overflows EQUALLY top and bottom rather than spilling only off the
                // bottom the way collapsed spacers would.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 24)
                .padding(.vertical, Self.outerVMargin)
                .animation(.snappy, value: settings.family)
            }
            // Centre in the FULL screen, matching the backdrop. Without this the
            // GeometryReader is inset by the safe area, so an asymmetric inset (big
            // top notch, small bottom) centres the card within that inset region —
            // which reads as pushed-below-centre and imbalanced against the
            // full-screen dim. The card is far smaller than the screen with a wide
            // margin, so it never reaches the notch or home indicator.
            .ignoresSafeArea()
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

    /// A plain card that HUGS its content; the outer frame centres it in the
    /// window. Both layouts are tuned to fit the shortest device (iPhone SE) — the
    /// pager in portrait, the sidebar in landscape — so neither needs a ScrollView.
    /// On a taller screen the card just centres with a larger even margin.
    private func card(layout: BoardSelectionPicker.Layout, width: CGFloat) -> some View {
        // The sidebar layout is chosen for short-wide viewports (landscape phone can
        // be only ~375pt tall), so it packs tighter than the pager: less title gap
        // and less card padding, keeping the whole card within that height.
        let sidebar = layout == .sidebar
        return VStack(spacing: sidebar ? 12 : 20) {
            Text("New game", bundle: .module).font(.title2.bold())
            picker(layout: layout)
            #if os(macOS)
            Text("Arrows to choose · Return to start", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
            #endif
            if layout == .pager {
                picker(layout: .pager).startButton
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, sidebar ? 16 : 24)
        .frame(width: width)
        // Clip to the rounded card so nothing a child lays out wider can spill past
        // the card edge (the card is already clamped to the window).
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
