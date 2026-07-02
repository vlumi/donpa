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
                card(
                    layout: Self.layout(for: geo.size),
                    width: Self.cardWidth(available: geo.size.width - 48)
                )
                // Bound the WHOLE card to the window (minus the outer margin each
                // side). A small vertical margin lets the card grow tall on a short
                // screen; the horizontal margin stays roomier so the card doesn't
                // hug the side edges.
                .frame(
                    maxWidth: .infinity, maxHeight: geo.size.height - 2 * Self.outerVMargin,
                    alignment: .center
                )
                .overlay(alignment: .topTrailing) { closeButton }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, Self.outerVMargin)
                .animation(.snappy, value: settings.family)
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
    private func card(layout: BoardSelectionPicker.Layout, width: CGFloat) -> some View {
        let inner = VStack(spacing: 20) {
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
        .padding(24)

        return Group {
            switch layout {
            case .pager:
                // The pager layout is tuned to fit the SHORTEST device (iPhone SE)
                // in portrait — so it fits every taller screen too. No ScrollView:
                // a plain card that hugs its content, which the outer frame then
                // centers.
                inner
            case .sidebar:
                // The sidebar layout (landscape phone / iPad / Mac) can meet a short
                // viewport, so it scrolls when it must — hugging its content and
                // centring otherwise (`.basedOnSize` + fixedSize; see scrollBehavior).
                scrollBehavior(ScrollView { inner })
            }
        }
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

    /// Make the card HUG its content vertically (a ScrollView is otherwise greedy
    /// and fills all offered height, stretching the card tall on a big screen).
    /// With `fixedSize`, the outer `maxHeight` frame becomes a real CAP: when the
    /// content fits it hugs and the outer frame centers it (equal top/bottom
    /// margin); when it's taller than the window it clamps and this scrolls. So the
    /// margin is effectively "minimum 0" — the card never grows past its content on
    /// a tall screen, and never overruns a short one.
    @ViewBuilder private func scrollBehavior(_ scroll: ScrollView<some View>) -> some View {
        let hugging = scroll.fixedSize(horizontal: false, vertical: true)
        if #available(iOS 16.4, macOS 13.3, *) {
            hugging.scrollBounceBehavior(.basedOnSize)
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
