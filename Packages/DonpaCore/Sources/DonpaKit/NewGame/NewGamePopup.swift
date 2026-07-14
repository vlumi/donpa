import DonpaCore
import SwiftUI

/// The new-game config chooser as a modal overlay — an overlay rather than a
/// `.sheet` so the dismiss affordances match the result screen across platforms.
struct NewGamePopup: View {
    @ObservedObject var settings: Settings
    var index = InProgressIndex(savedConfigs: [])
    var gates = UnlockGates.open

    let onStart: () -> Void
    let onClose: () -> Void
    var onResume: ((GameConfig) -> Void)?

    #if os(macOS)
    @State private var keyboardFocusedRow: Int?
    #endif

    /// Fixed across all family pages so paging never resizes the frame.
    private static let idealWidth: CGFloat = 680

    private static let outerVMargin: CGFloat = 12

    /// Any landscape phone clears this width; a portrait phone doesn't.
    private static let sidebarMinWidth: CGFloat = 600

    /// Layout chosen by the viewport shape, not the platform.
    private static func layout(for viewport: CGSize) -> BoardSelectionPicker.Layout {
        viewport.width >= sidebarMinWidth ? .sidebar : .pager
    }

    private static func cardWidth(available: CGFloat) -> CGFloat {
        min(Self.idealWidth, max(0, available))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }

            GeometryReader { geo in
                card(
                    layout: Self.layout(for: geo.size),
                    width: Self.cardWidth(available: geo.size.width - 48),
                    // Every landscape-phone-height window packs compact; since
                    // compact keeps the taglines (merged onto the facts line),
                    // nothing is lost. iPad/Mac landscape keep two-line captions.
                    short: geo.size.height < 480
                )
                // The X lives on the card (its actual width), so it sits in the
                // card's corner rather than the screen's.
                .overlay(alignment: .topTrailing) { closeButton }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 24)
                .padding(.vertical, Self.outerVMargin)
                .animation(FamilySwitch.animation, value: settings.family)
            }
            // Ignore the safe area so the card centres in the same full-screen space
            // the backdrop covers; an asymmetric inset would otherwise push it below
            // centre. The card is small with a wide margin, so it clears the notch.
            .ignoresSafeArea()
        }
        #if os(macOS)
        // AppKit key-catcher: @FocusState can't reliably take first responder from
        // the SpriteKit board, especially after a game ends.
        .background(KeyCatcher { handleKey($0) })
        #endif
        .onAppear { sanitizeSelection() }
    }

    /// A persisted selection can point at a locked option (a fresh-gates debug
    /// run, or a future stats reset): step each locked axis down to its best
    /// unlocked value so the picker never opens onto a dead selection. The
    /// family stays put — a locked family shows its teaser page, which is the
    /// desired landing.
    private func sanitizeSelection() {
        for path in [\Settings.gridSize, \Settings.hiveSize]
        where
            !gates.size(settings[keyPath: path])
        {
            settings[keyPath: path] = BoardSize.allCases.filter(gates.size).last ?? .s
        }
        if !gates.size(settings.practiceSize) {
            settings.practiceSize =
                GameConfig.practiceSizes.filter(gates.size).last ?? .s
        }
        for path in [\Settings.gridDensity, \Settings.hiveDensity]
        where
            !gates.rank(settings[keyPath: path])
        {
            settings[keyPath: path] = Density.allCases.filter(gates.rank).last ?? .normal
        }
        for path in [\Settings.gridEdges, \Settings.hiveEdges]
        where
            !gates.edges(settings[keyPath: path])
        {
            settings[keyPath: path] = .flat
        }
    }

    #if os(macOS)
    private func handleKey(_ key: KeyCatcher.Key) {
        switch key {
        // Family is picked by number (⌘1/2/3), not arrowed through — it's a list of
        // distinct board types, not a value to step. Arrows drive the OTHER rows.
        case .family(let n): pickFamily(n)
        // Basic's presets are a single VERTICAL list, so ↑/↓ step through them
        // (matching their layout); ←/→ do the same for good measure. Grid/Hive have
        // multiple horizontal chip-rows, so ↑/↓ move BETWEEN rows and ←/→ cycle within.
        case .up, .backTab: stepRow(-1)
        case .down, .tab: stepRow(1)
        case .left: cycleSelection(in: keyboardFocusedRow ?? 0, by: -1)
        case .right: cycleSelection(in: keyboardFocusedRow ?? 0, by: 1)
        case .enter: commitSelection()
        case .escape: onClose()
        case .character: break  // no letter actions on this surface
        case .space: break  // Space stays the board's mode key, not a commit
        case .click: keyboardFocusedRow = nil  // mouse takes over; the ring stands down
        }
    }

    /// ↑/↓ (and Tab): Basic's presets are a single vertical list, so they step
    /// the selection; Grid/Hive step BETWEEN rows (←/→ cycle within one).
    private func stepRow(_ delta: Int) {
        if settings.family == .basic {
            cycleSelection(in: 0, by: delta)
        } else if delta < 0 {
            keyboardFocusedRow = max(0, (keyboardFocusedRow ?? 0) - 1)
        } else {
            keyboardFocusedRow = min(rowCount - 1, (keyboardFocusedRow ?? -1) + 1)
        }
    }

    private func pickFamily(_ n: Int) {
        let families = BoardFamily.allCases
        if (1...families.count).contains(n) {
            settings.family = families[n - 1]
            keyboardFocusedRow = nil
        }
    }

    /// Return does what the button does: Continue the current selection if it has an
    /// in-progress save, else Start fresh — matching `BoardSelectionPicker.canContinue`
    /// so the key never diverges from the visible Start/Continue label.
    private func commitSelection() {
        if let onResume, index.hasSave(for: settings.currentConfig) {
            onResume(settings.currentConfig)
        } else {
            onStart()
        }
    }

    /// Arrow-navigable rows in the current family (family excluded — it's ⌘1–4):
    /// Basic and Drills have one (preset / size); Grid/Hive have three
    /// (size, density, edges).
    private var rowCount: Int {
        switch settings.family {
        case .basic, .practice: return 1
        case .grid, .hive: return 3
        }
    }
    #endif

    /// A card that hugs its content; the outer frame centres it. Tuned to fit
    /// the shortest device (iPhone SE) at default text; when accessibility text
    /// outgrows that, the picker body scrolls so the pinned title and Start
    /// never leave the screen. Start sits full-width at the card's BOTTOM in
    /// both layouts — a confirm anywhere else gets mis-tapped. `short`
    /// (landscape phone) compensates for that row via the picker's compact mode.
    private func card(
        layout: BoardSelectionPicker.Layout, width: CGFloat, short: Bool
    ) -> some View {
        // The sidebar is the short-wide layout (landscape phone ~375pt tall), so it
        // packs tighter than the pager: less title gap and less card padding.
        let sidebar = layout == .sidebar
        return VStack(spacing: sidebar ? (short ? 8 : 12) : 20) {
            Text("New game", bundle: .module).font(short ? .headline : .title2.bold())
            ViewThatFits(in: .vertical) {
                pickerBody(layout: layout, short: short)
                ScrollView { pickerBody(layout: layout, short: short) }
            }
            picker(layout: layout, compact: short).startButton
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, sidebar ? (short ? 10 : 16) : 24)
        .frame(width: width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 6)
    }

    /// The scrollable middle of the card: the picker (and the macOS key legend),
    /// between the pinned title and Start.
    @ViewBuilder private func pickerBody(
        layout: BoardSelectionPicker.Layout, short: Bool
    ) -> some View {
        let sidebar = layout == .sidebar
        VStack(spacing: sidebar ? (short ? 8 : 12) : 20) {
            picker(layout: layout, compact: short)
            #if os(macOS)
            Text("⌘1–4 family · arrows to choose · Return to start", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
            #endif
        }
    }

    /// The `BoardSelectionPicker` for a layout.
    private func picker(
        layout: BoardSelectionPicker.Layout, compact: Bool = false
    ) -> BoardSelectionPicker {
        #if os(macOS)
        BoardSelectionPicker(
            settings: settings, keyboardFocusedRow: keyboardFocusedRow,
            layout: layout, compact: compact,
            index: index, gates: gates, onStart: onStart, onResume: onResume)
        #else
        BoardSelectionPicker(
            settings: settings, layout: layout, compact: compact,
            index: index, gates: gates, onStart: onStart, onResume: onResume)
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
    /// Cycle the value in the focused row (family is NOT a row — it's ⌘1/2/3).
    /// Basic: the sole row is the preset. Grid/Hive: 0 = size, 1 = density, 2 = edges
    /// (the hierarchy order, matching the visual rows + in-progress drill-down).
    private func cycleSelection(in row: Int, by step: Int) {
        switch (settings.family, row) {
        case (.basic, _):
            settings.basicPreset = KeyStep.clamped(settings.basicPreset, by: step)
        case (.practice, _):  // size is Drills' only row — clamped to ITS ladder
            settings.practiceSize = KeyStep.clamped(
                settings.practiceSize, by: step,
                within: GameConfig.practiceSizes.filter(gates.size))
        case (.grid, 0), (.hive, 0):
            let path = Settings.sizePath(settings.family)
            settings[keyPath: path] = KeyStep.clamped(
                settings[keyPath: path], by: step,
                within: BoardSize.allCases.filter(gates.size))
        case (.grid, 1), (.hive, 1):
            let path = Settings.densityPath(settings.family)
            settings[keyPath: path] = KeyStep.clamped(
                settings[keyPath: path], by: step,
                within: Density.allCases.filter(gates.rank))
        case (.grid, _), (.hive, _):  // row 2: edges
            let path = Settings.edgesPath(settings.family)
            settings[keyPath: path] = KeyStep.clamped(
                settings[keyPath: path], by: step,
                within: BoardEdges.allCases.filter(gates.edges))
        }
    }

    #endif
}
