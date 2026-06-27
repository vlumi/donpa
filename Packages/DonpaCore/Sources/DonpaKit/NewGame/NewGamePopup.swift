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

    var body: some View {
        ZStack {
            // Dimmed backdrop: blocks what's behind and dismisses when tapped.
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }

            card
                .overlay(alignment: .topTrailing) { closeButton }
                .padding(24)
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
            let rows = settings.mode == .classic ? 2 : 3
            focusedRow = min(rows - 1, (focusedRow ?? -1) + 1)
        case .left: cycleSelection(in: focusedRow ?? 0, by: -1)
        case .right: cycleSelection(in: focusedRow ?? 0, by: 1)
        case .enter: onStart()
        case .escape: onClose()
        }
    }
    #endif

    private var card: some View {
        VStack(spacing: 20) {
            Text("New game", bundle: .module).font(.title2.bold())

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
        .padding(24)
        .frame(maxWidth: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 6)
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
    /// Cycle the selection in the given row. Row 0 is Mode; rows 1+ are Difficulty
    /// (Classic), or Difficulty then Size (Modern).
    private func cycleSelection(in row: Int, by step: Int) {
        switch (settings.mode, row) {
        case (_, 0):
            settings.mode = settings.mode == .classic ? .modern : .classic
        case (.classic, _):
            settings.classicPreset = Self.stepped(settings.classicPreset, by: step)
        case (.modern, 1):
            settings.modernDensity = Self.stepped(settings.modernDensity, by: step)
        case (.modern, _):
            settings.modernSize = Self.stepped(settings.modernSize, by: step)
        }
    }

    /// Next/previous case of a `CaseIterable` enum, clamped at the ends (no wrap),
    /// matching the carousel.
    private static func stepped<T: CaseIterable & Equatable>(_ value: T, by step: Int) -> T {
        let all = Array(T.allCases)
        guard let i = all.firstIndex(of: value), !all.isEmpty else { return value }
        let next = min(max(i + step, 0), all.count - 1)
        return all[next]
    }
    #endif
}
