import DonpaCore
import SwiftUI

/// The board-config chooser for the three **families** (Basic / Grid / Hive).
/// Basic is three preset cards; Grid and Hive share the difficulty chips, size
/// chips, and Flat/Round edges toggle. Two layouts (see `Layout`): a swipe-pager
/// under a glyph tab strip, or a family sidebar beside a detail pane. Graphical by
/// design — family glyphs, rank-insignia difficulty, map/globe edges. Binds
/// directly to `Settings`; the host decides when to start. macOS is keyboard-
/// drivable: up/down move rows, left/right cycle the focused row (row 0 = family).
struct BoardSelectionPicker: View {
    /// A tapped locked option's teaser, shown briefly in a fixed caption slot
    /// (0 = the size row's, 1 = the density row's — edges borrows the density
    /// slot) so the page's height never changes.
    struct LockedHint: Equatable {
        let slot: Int
        let text: String
        let id = UUID()
        static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    }

    @ObservedObject var settings: Settings
    /// Keyboard-focused row, or nil when not keyboard-driven (iOS, or before the
    /// first arrow press).
    var focusedRow: Int?
    /// Ask the host to move keyboard focus to a row. nil on iOS.
    var onFocusRow: ((Int) -> Void)?

    /// Which layout to render — the host picks by viewport shape (narrow portrait
    /// phone → pager; anything wider → sidebar). Not a platform/size-class split.
    enum Layout { case pager, sidebar }
    var layout: Layout = .pager
    @State var lockedHint: LockedHint?
    /// Start the game with the current selection. The picker owns the Start button
    /// so each layout can place it (sidebar: below its column; pager: the host pins
    /// it full-width below).
    var onStart: () -> Void = {}
    /// Which configs have an in-progress save — drives the Start→Continue button swap
    /// and the drill-down dots on the selector chips.
    var index = InProgressIndex(savedConfigs: [])
    /// Progressive gating (see `UnlockEngine`); `.open` = no gating (previews).
    var gates = UnlockGates.open
    /// Resume the saved game for a config (when the current selection has one). nil →
    /// the button is always Start.
    var onResume: ((GameConfig) -> Void)?
    /// Short-window mode (landscape phone): captions drop their tagline line and the
    /// Start button slims — that buys back the height of the full-width Start row at
    /// the card's bottom, so nothing scrolls on a landscape SE.
    var compact = false

    /// Chip/caption line boxes scale with the text they hold (Dynamic Type) — a
    /// hard 22pt clipped grown labels vertically. Scaled as a set (and the
    /// insignia with them) so the rows keep their relative proportions; at the
    /// default size nothing changes.
    @ScaledMetric(relativeTo: .subheadline) var chipContentHeight: CGFloat = 22
    @ScaledMetric(relativeTo: .subheadline) var insigniaWidth: CGFloat = 36
    @ScaledMetric(relativeTo: .body) var captionLineHeight: CGFloat = 22

    /// The current selection has a save AND we can resume it → the button says Continue.
    private var canContinue: Bool {
        onResume != nil && index.hasSave(for: settings.currentConfig)
    }

    /// Live drag offset while swiping the pager; snaps back with the same
    /// spring the page change uses, so release always lands smoothly.
    @GestureState(resetTransaction: Transaction(animation: .snappy))
    private var pagerDrag: CGFloat = 0
    /// The pager's slot width (one page), measured from layout.
    @State private var pagerWidth: CGFloat = 0
    /// Measured natural height per page; the slot is fixed at the tallest one.
    @State private var pageHeights: [BoardFamily: CGFloat] = [:]

    var body: some View {
        switch layout {
        case .sidebar: regularLayout
        case .pager: compactLayout
        }
    }

    /// Compact (portrait phone): the tab strip over the swipe-pager. The host pins
    /// Start below this, so nothing here renders it.
    private var compactLayout: some View {
        VStack(spacing: 14) {
            familyTabs  // family: tap a tab / swipe the pager (⌘1-3 on Mac) — not arrowed

            pager
        }
    }

    // MARK: Regular layout (iPad / Mac / landscape) — family sidebar + detail pane

    /// Regular: a family sidebar beside the detail pane; the host pins Start below
    /// BOTH columns (bottom-right is where a confirm belongs — with Start bottom-left
    /// under the families, the Flat/Round toggle sat in the "start" position and got
    /// tapped as one). Both columns hug their content; the card hugs the taller.
    private var regularLayout: some View {
        HStack(alignment: .top, spacing: 20) {
            familySidebar  // family: click a row (⌘1-3 on Mac) — not arrowed
                .frame(width: 160)
            detailPaneStack
                .frame(maxWidth: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)  // hug height; don't fill the window
    }

    /// The Start button — a filled capsule. Placed by each layout (see `onStart`).
    /// Becomes **Continue** (and resumes) when the current selection has an in-progress
    /// save, so you pick the board up where you left it instead of restarting it.
    var startButton: some View {
        let locked = !gates.config(settings.currentConfig)
        return Button {
            guard !locked else { return }
            if canContinue {
                onResume?(settings.currentConfig)
            } else {
                onStart()
            }
        } label: {
            Label {
                Text(canContinue ? "Continue" : "Start", bundle: .module)
            } icon: {
                Image(systemName: canContinue ? "arrow.uturn.forward.circle.fill" : "play.fill")
            }
            .font(.title3.weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 8 : 12)
            .background(Color.accentColor.opacity(locked ? 0.45 : 1), in: Capsule())
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(locked)  // a locked selection (the Hive teaser page) can't start
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("newgame.start")
        .task(id: lockedHint) {
            // The teaser lines are transient — clear after a beat.
            guard lockedHint != nil else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            lockedHint = nil
        }
    }

    /// All families' panes stacked, only the selected one shown — so the pane is
    /// sized to the tallest family and switching families never changes the height.
    private var detailPaneStack: some View {
        ZStack(alignment: .top) {
            ForEach(BoardFamily.allCases) { family in
                detailPane(for: family)
                    .opacity(family == settings.family ? 1 : 0)
                    .accessibilityHidden(family != settings.family)
                    .allowsHitTesting(family == settings.family)
            }
        }
    }

    private var familySidebar: some View {
        VStack(spacing: 8) {
            ForEach(BoardFamily.allCases) { family in
                familySidebarItem(family)
            }
        }
    }

    /// The detail pane: the chosen family's options, filling the width. Same content
    /// as a pager page (`familyContent`) — the sidebar just packs the Grid/Hive rows
    /// a touch tighter, since it's the short-wide layout.
    private func detailPane(for family: BoardFamily) -> some View {
        familyContent(for: family, gridHiveSpacing: 8, distribute: true)
    }

    /// Move to the previous/next family page, clamped at the ends.
    private func step(family delta: Int) {
        let all = BoardFamily.allCases
        guard let i = all.firstIndex(of: settings.family) else { return }
        let next = min(max(i + delta, 0), all.count - 1)
        withAnimation(.snappy) { settings.family = all[next] }
    }

    // MARK: Sliding pager

    private var selectedIndex: Int {
        BoardFamily.allCases.firstIndex(of: settings.family) ?? 0
    }

    /// All three pages side by side, offset to the selected one plus the live drag,
    /// so the swipe is visible and interruptible. The slot width comes from a
    /// dedicated ruler, not the sliding content, which would feed its own frame
    /// back into the layout.
    private var pager: some View {
        // Render the pages only once the slot width is measured, so the first
        // layout is already at the constrained width (an unconstrained placeholder
        // made ViewThatFits see infinite width and never wrap). Until then, show a
        // zero-content ruler whose width sets `pagerWidth`.
        Group {
            if pagerWidth > 0 {
                slidingPages
            } else {
                Color.clear.frame(maxWidth: .infinity, minHeight: 1)
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: PagerWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(PagerWidthKey.self) { width in
            guard width > 0 else { return }
            pagerWidth = width
        }
    }

    /// How far each neighbouring page peeks in at the slot's edges — the standing
    /// hint that there's more to swipe to — and the gap between the framed panels.
    private static let pagePeek: CGFloat = 24
    private static let pageGap: CGFloat = 10

    private var slidingPages: some View {
        // Panels narrower than the slot, so neighbours peek in as a "there's more"
        // cue; the edge mask fades those peeks instead of hard-cutting them.
        let pageWidth = pagerWidth - 2 * Self.pagePeek
        let stride = pageWidth + Self.pageGap
        return HStack(alignment: .top, spacing: Self.pageGap) {
            ForEach(BoardFamily.allCases) { family in
                pagePanel(for: family, width: pageWidth)
            }
        }
        .offset(x: -CGFloat(selectedIndex) * stride + Self.pagePeek + rubberBanded(pagerDrag))
        .frame(width: pagerWidth, height: pageHeights.values.max(), alignment: .topLeading)
        .mask(edgeFadeMask)
        .contentShape(Rectangle())
        .simultaneousGesture(pagerGesture)
        .onPreferenceChange(PageHeightsKey.self) { heights in
            pageHeights.merge(heights) { _, new in new }
        }
    }

    /// Opaque across the middle, fading to clear at each edge so a peeking neighbour
    /// dissolves instead of being sliced. Narrow, keeping the selected panel crisp.
    private var edgeFadeMask: some View {
        let fade = (Self.pagePeek + Self.pageGap) / max(pagerWidth, 1)
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: fade),
                .init(color: .black, location: 1 - fade),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading, endPoint: .trailing)
    }

    /// One page as a faintly-bordered panel, stretched to the fixed slot height so
    /// the peeking neighbours read as equal cards.
    private func pagePanel(for family: BoardFamily, width: CGFloat) -> some View {
        page(for: family)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .frame(width: width, alignment: .top)
            // Measure natural height BEFORE the stretch below; measuring after would
            // feed the stretched height back into the slot and inflate the panel.
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: PageHeightsKey.self,
                        value: [family: geo.size.height])
                }
            )
            // Centre, not top: the slot is sized to the TALLEST family, so a
            // short page (Drills' two rows) top-aligned left a dead area below;
            // centred it reads as composed. (Measured before this stretch, so
            // the centring can't feed back into the slot height.)
            .frame(maxHeight: .infinity, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.primary.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.primary.opacity(0.10), lineWidth: 1))
            )
    }

    /// Damp the pull past the first/last page, so the edge answers with
    /// resistance instead of silently ignoring the swipe.
    private func rubberBanded(_ x: CGFloat) -> CGFloat {
        let atStart = selectedIndex == 0 && x > 0
        let atEnd = selectedIndex == BoardFamily.allCases.count - 1 && x < 0
        return (atStart || atEnd) ? x / 3 : x
    }

    private var pagerGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .updating($pagerDrag) { value, state, _ in
                state = value.translation.width
            }
            .onEnded { value in
                // A quarter-page pull or a decisive fling turns the page.
                let threshold = pagerWidth / 4
                let projected = value.predictedEndTranslation.width
                if value.translation.width < -threshold || projected < -pagerWidth / 2 {
                    step(family: 1)
                } else if value.translation.width > threshold || projected > pagerWidth / 2 {
                    step(family: -1)
                }
            }
    }

    // MARK: Family tabs (row 0)

    private var familyTabs: some View {
        HStack(spacing: 18) {
            ForEach(BoardFamily.allCases) { family in
                familyTab(family)
            }
        }
    }

    // MARK: Pages

    private func page(for family: BoardFamily) -> some View {
        // Fixed spacing, NOT distribution: the pager sizes its slot by MEASURING the
        // pages, and greedy (Spacer-filled) content expands to whatever's proposed —
        // the measurement then reports that stretched height, ratcheting the card up
        // until it filled the screen and pushed Close behind the Dynamic Island.
        familyContent(for: family, gridHiveSpacing: 12, distribute: false)
    }

    /// A family's option rows, shared by the pager page and the sidebar detail pane.
    /// Basic is its three preset cards; Grid/Hive are the difficulty / size / edges
    /// rows, stacked with the caller's spacing (the pager breathes a little more,
    /// the short-wide sidebar packs tighter).
    @ViewBuilder private func familyContent(
        for family: BoardFamily, gridHiveSpacing: CGFloat, distribute: Bool
    ) -> some View {
        switch family {
        case _ where !gates.family(family):
            // The teaser page: the family stays visible — seeing the next rung
            // is the point — but its rows wait behind the requirement.
            VStack(spacing: 10) {
                BoardGlyph(kind: .family(family), size: 52)
                    .opacity(0.5)
                detailLine(
                    detail: String(localized: "Locked", bundle: .module),
                    tagline: UnlockGates.requirementText(.winAnySquare))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .accessibilityElement(children: .combine)
        case .basic:
            basicCards
        case .practice:
            // Size is Drills' only axis (density fixed, edges Flat); the creed
            // line stands where Grid/Hive show their density row.
            VStack(spacing: distribute ? 0 : gridHiveSpacing) {
                sizeChips(for: family)
                    .modifier(FocusRing(focused: focusedRow == 0, inset: compact ? 3 : 6))
                if distribute { Spacer(minLength: gridHiveSpacing) }
                practiceCreed
            }
            .frame(maxHeight: distribute ? .infinity : nil)
        case .grid, .hive:
            // Hierarchy order (matches the in-progress drill-down + keyboard rows):
            // size → density → edges. Size is the fundamental scale; density tunes it.
            // In the SIDEBAR (`distribute`), spacers spread the rows over the pane —
            // it's sized to the tallest family (Basic's three preset cards), so fixed
            // spacing left Basic's extra height as a dead gap under the edges row;
            // the sidebar's `fixedSize` measures the IDEAL height, so greedy spacers
            // are safe there (unlike the pager — see `page(for:)`). On an
            // exactly-fitting window they collapse to the plain spacing.
            VStack(spacing: distribute ? 0 : gridHiveSpacing) {
                sizeChips(for: family)
                    .modifier(FocusRing(focused: focusedRow == 0, inset: compact ? 3 : 6))
                if distribute { Spacer(minLength: gridHiveSpacing) }
                densityChips(for: family)
                    .modifier(FocusRing(focused: focusedRow == 1, inset: compact ? 3 : 6))
                if distribute { Spacer(minLength: gridHiveSpacing) }
                edgesToggle(for: family)
                    .modifier(FocusRing(focused: focusedRow == 2, inset: compact ? 3 : 6))
            }
            .frame(maxHeight: distribute ? .infinity : nil)
        }
    }
}

/// Layout feedback for the sliding pager: the slot width and each page's height.
private struct PagerWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct PageHeightsKey: PreferenceKey {
    static var defaultValue: [BoardFamily: CGFloat] = [:]
    static func reduce(
        value: inout [BoardFamily: CGFloat], nextValue: () -> [BoardFamily: CGFloat]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}
