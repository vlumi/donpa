import DonpaCore
import SwiftUI

/// Family-switch animation: the sliding pager on iOS wants the motion, but a
/// clicked macOS tab expects an instant swap — the cross-animation reads as
/// ghosting there.
enum FamilySwitch {
    static var animation: Animation? {
        #if os(macOS)
        return nil
        #else
        return .snappy
        #endif
    }
}

struct BoardSelectionPicker: View {
    /// A tapped locked option's teaser, shown in a fixed caption slot (0 = the
    /// size row's, 1 = the density row's — edges borrows the density slot) so
    /// the page's height never changes.
    struct LockedHint: Equatable {
        let slot: Int
        let text: String
        let id = UUID()
        static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    }

    enum Layout { case pager, sidebar }

    @ObservedObject var settings: Settings
    var keyboardFocusedRow: Int?
    var layout: Layout = .pager
    /// Short-window packing (landscape phone), not the size class: captions
    /// merge to one line and the Start button slims.
    var compact = false
    var index = InProgressIndex(savedConfigs: [])
    var gates = UnlockGates.open

    var onStart: () -> Void = {}
    var onResume: ((GameConfig) -> Void)?

    @State var lockedHint: LockedHint?
    @State private var pagerWidth: CGFloat = 0
    @State private var pageHeights: [BoardFamily: CGFloat] = [:]
    /// Snaps back with the same spring the page change uses.
    @GestureState(resetTransaction: Transaction(animation: .snappy))
    private var pagerDrag: CGFloat = 0

    /// Scaled as a set with Dynamic Type — a hard 22pt clipped grown labels.
    @ScaledMetric(relativeTo: .subheadline) var chipContentHeight: CGFloat = 22
    @ScaledMetric(relativeTo: .subheadline) var insigniaWidth: CGFloat = 36
    @ScaledMetric(relativeTo: .body) var captionLineHeight: CGFloat = 22

    private var canContinue: Bool {
        onResume != nil && index.hasSave(for: settings.currentConfig)
    }

    var body: some View {
        switch layout {
        case .sidebar: regularLayout
        case .pager: compactLayout
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 14) {
            familyTabs  // family: tap a tab / swipe the pager (⌘1-3 on Mac) — not arrowed

            pager
        }
    }

    // MARK: Regular layout (sidebar + detail pane)

    private var regularLayout: some View {
        HStack(alignment: .top, spacing: 20) {
            familySidebar  // family: click a row (⌘1-3 on Mac) — not arrowed
                .frame(width: 160)
            detailPaneStack
                .frame(maxWidth: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

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
        .disabled(locked)
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("newgame.start")
        .task(id: lockedHint) {
            guard lockedHint != nil else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            lockedHint = nil
        }
    }

    /// All panes stacked, only the selected one shown, so the pane is sized to
    /// the tallest family and switching never changes the height.
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

    private func detailPane(for family: BoardFamily) -> some View {
        familyContent(for: family, gridHiveSpacing: 8, distribute: true)
    }

    private func step(family delta: Int) {
        let all = BoardFamily.allCases
        guard let i = all.firstIndex(of: settings.family) else { return }
        let next = min(max(i + delta, 0), all.count - 1)
        withAnimation(FamilySwitch.animation) { settings.family = all[next] }
    }

    // MARK: Sliding pager

    private var selectedIndex: Int {
        BoardFamily.allCases.firstIndex(of: settings.family) ?? 0
    }

    private var pager: some View {
        // Render the pages only once the slot width is measured: an unconstrained
        // placeholder made ViewThatFits see infinite width and never wrap. Until
        // then, a zero-content ruler sets `pagerWidth`.
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
                    .modifier(FocusRing(focused: keyboardFocusedRow == 0, inset: compact ? 3 : 6))
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
                    .modifier(FocusRing(focused: keyboardFocusedRow == 0, inset: compact ? 3 : 6))
                if distribute { Spacer(minLength: gridHiveSpacing) }
                densityChips(for: family)
                    .modifier(FocusRing(focused: keyboardFocusedRow == 1, inset: compact ? 3 : 6))
                if distribute { Spacer(minLength: gridHiveSpacing) }
                edgesToggle(for: family)
                    .modifier(FocusRing(focused: keyboardFocusedRow == 2, inset: compact ? 3 : 6))
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
