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
    /// In-progress saves — drives the Start→Continue swap + the selector dots.
    var index = InProgressIndex(savedConfigs: [])
    /// Resume the saved game for a config. nil → the button is always Start.
    var onResume: ((GameConfig) -> Void)?
    /// Progressive gating; `.open` = no gating (previews/tests).
    var gates = UnlockGates.open

    #if os(macOS)
    /// Keyboard-focused picker row (0 = Mode). nil until the first arrow press.
    @State private var focusedRow: Int?
    #endif

    /// Card width, fixed across all family pages so paging never resizes the frame.
    private static let idealWidth: CGFloat = 680

    /// Gap between the card and the window edge.
    private static let outerVMargin: CGFloat = 12

    /// At/above this width the modal uses the sidebar layout; below it (portrait
    /// phone), the pager. Any landscape phone clears it; a portrait phone doesn't.
    private static let sidebarMinWidth: CGFloat = 600

    /// Layout chosen by the viewport SHAPE, not the platform — runtime, no `#if os`.
    private static func layout(for viewport: CGSize) -> BoardSelectionPicker.Layout {
        viewport.width >= sidebarMinWidth ? .sidebar : .pager
    }

    /// The ideal width, clamped to what the window allows so the card never spills
    /// past the edge (the chip rows wrap to fit a narrow window).
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

            GeometryReader { geo in
                card(
                    layout: Self.layout(for: geo.size),
                    width: Self.cardWidth(available: geo.size.width - 48),
                    // Every landscape-phone-height window packs compact (SE proved
                    // the fit; the 17 Pro clipped without it) — since compact keeps
                    // the taglines (merged onto the facts line), it's no longer a
                    // trade-off. iPad/Mac landscape (600pt+) keep two-line captions.
                    short: geo.size.height < 480
                )
                // The X lives on the card (its actual width), so it sits in the
                // card's corner rather than the screen's.
                .overlay(alignment: .topTrailing) { closeButton }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 24)
                .padding(.vertical, Self.outerVMargin)
                .animation(.snappy, value: settings.family)
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
        case .left: cycleSelection(in: focusedRow ?? 0, by: -1)
        case .right: cycleSelection(in: focusedRow ?? 0, by: 1)
        case .enter: commitSelection()
        case .escape: onClose()
        case .character: break  // no letter actions on this surface
        case .space: break  // Space stays the board's mode key, not a commit
        }
    }

    /// ↑/↓ (and Tab): Basic's presets are a single vertical list, so they step
    /// the selection; Grid/Hive step BETWEEN rows (←/→ cycle within one).
    private func stepRow(_ delta: Int) {
        if settings.family == .basic {
            cycleSelection(in: 0, by: delta)
        } else if delta < 0 {
            focusedRow = max(0, (focusedRow ?? 0) - 1)
        } else {
            focusedRow = min(rowCount - 1, (focusedRow ?? -1) + 1)
        }
    }

    private func pickFamily(_ n: Int) {
        let families = BoardFamily.allCases
        if (1...families.count).contains(n) {
            settings.family = families[n - 1]
            focusedRow = nil  // reset focus into the new family's rows
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
    /// both layouts — the confirm belongs at the bottom edge (with Start under
    /// the family sidebar, the Flat/Round toggle got tapped as Start). `short`
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
            settings: settings, focusedRow: focusedRow,
            onFocusRow: { focusedRow = $0 }, layout: layout, onStart: onStart,
            index: index, gates: gates, onResume: onResume, compact: compact)
        #else
        BoardSelectionPicker(
            settings: settings, layout: layout, onStart: onStart,
            index: index, gates: gates, onResume: onResume, compact: compact)
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
    /// Cycle the value in the focused row (family is NOT a row — it's ⌘1/2/3).
    /// Basic: the sole row is the preset. Grid/Hive: 0 = size, 1 = density, 2 = edges
    /// (the hierarchy order, matching the visual rows + in-progress drill-down).
    private func cycleSelection(in row: Int, by step: Int) {
        switch (settings.family, row) {
        case (.basic, _):
            settings.basicPreset = Self.stepped(settings.basicPreset, by: step)
        case (.practice, _):  // size is Drills' only row — clamped to ITS ladder
            settings.practiceSize = Self.stepped(
                settings.practiceSize, by: step,
                within: GameConfig.practiceSizes.filter(gates.size))
        case (.grid, 0), (.hive, 0):
            let path = Settings.sizePath(settings.family)
            settings[keyPath: path] = Self.stepped(
                settings[keyPath: path], by: step,
                within: BoardSize.allCases.filter(gates.size))
        case (.grid, 1), (.hive, 1):
            let path = Settings.densityPath(settings.family)
            settings[keyPath: path] = Self.stepped(
                settings[keyPath: path], by: step,
                within: Density.allCases.filter(gates.rank))
        case (.grid, _), (.hive, _):  // row 2: edges
            let path = Settings.edgesPath(settings.family)
            settings[keyPath: path] = Self.stepped(
                settings[keyPath: path], by: step,
                within: BoardEdges.allCases.filter(gates.edges))
        }
    }

    /// Next/previous case of a `CaseIterable` enum, clamped at the ends (no
    /// wrap), matching the chip rows.
    private static func stepped<T: CaseIterable & Equatable>(_ value: T, by step: Int) -> T {
        stepped(value, by: step, within: Array(T.allCases))
    }

    /// The same, over an explicit ladder — for a family whose chips show only a
    /// slice of the enum (Drills' XS–XL).
    private static func stepped<T: Equatable>(_ value: T, by step: Int, within all: [T]) -> T {
        guard let i = all.firstIndex(of: value), !all.isEmpty else { return all.first ?? value }
        let next = min(max(i + step, 0), all.count - 1)
        return all[next]
    }
    #endif
}
