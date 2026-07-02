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
                    width: Self.cardWidth(available: geo.size.width - 48),
                    maxHeight: geo.size.height - 48
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
    private func card(width: CGFloat, maxHeight: CGFloat) -> some View {
        VStack(spacing: 20) {
            Text("New game", bundle: .module).font(.title2.bold())

            scrollableContent
                // Hug content until it would overflow; only then cap + scroll.
                .frame(height: min(contentHeight, max(0, maxHeight)))
                .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
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

    /// The picker + Start button in a ScrollView (engages only when the card hits
    /// its height cap; suppresses rubber-banding when it doesn't, where available).
    @ViewBuilder private var scrollableContent: some View {
        let scroll = ScrollView {
            VStack(spacing: 20) {
                #if os(macOS)
                BoardSelectionPicker(
                    settings: settings, focusedRow: focusedRow,
                    onFocusRow: { focusedRow = $0 })
                Text("Arrows to choose · Return to start", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #else
                BoardSelectionPicker(settings: settings)
                #endif

                startButton
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

    private var startButton: some View {
        Button {
            onStart()
        } label: {
            Label {
                Text("Start", bundle: .module)
            } icon: {
                Image(systemName: "play.fill")
            }
            .font(.title3.weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.accentColor, in: Capsule())
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("newgame.start")
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
