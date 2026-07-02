import DonpaCore
import SwiftUI

/// The board-config chooser: three paged **families** (Basic / Grid / Hive) under
/// a glyph tab strip. Basic shows its three preset cards; Grid and Hive share one
/// page layout — rank-insignia difficulty chips, a size-chip row, and the
/// Flat/Round edges glyph toggle. Every option is always visible: no row scrolls
/// horizontally, so the pager owns that axis alone. Binds directly to
/// `Settings` — the pending choice; the host decides when to start a game.
///
/// Graphical by design: the family is its tab glyph, edges are two equal glyph
/// pictures (framed map ↔ globe), difficulty is the rank insignia. The pages sit
/// side by side and SLIDE — the content tracks a drag (finger or mouse),
/// rubber-bands at the ends, and snaps a page over on release; a tab tap slides
/// the same way, so both platforms share one behaviour. On macOS it's also
/// keyboard-drivable — up/down move between rows, left/right cycle within the
/// focused row (row 0 = the tabs).
struct BoardSelectionPicker: View {
    @ObservedObject var settings: Settings
    /// Keyboard-focused row, or nil when not keyboard-driven (iOS, or before the
    /// first arrow press).
    var focusedRow: Int?
    /// Ask the host to move keyboard focus to a row. nil on iOS.
    var onFocusRow: ((Int) -> Void)?

    /// Which of the two layouts to render. Chosen by the host from the actual
    /// viewport SHAPE, not the platform or size class: only a narrow, tall
    /// viewport (portrait phone) gets the vertical swipe-pager; everything wider
    /// (landscape phone, iPad, Mac) gets the sidebar + detail, which suits a
    /// short-wide shape and fills the width. `#if os` isn't used for this.
    enum Layout { case pager, sidebar }
    var layout: Layout = .pager
    /// Start the game with the current selection. The picker owns the Start button
    /// so each layout can PLACE it correctly (sidebar: bottom of the sidebar
    /// column; pager: full-width, pinned by the host below the scroll) — and so
    /// Start always sits OUTSIDE any scroll region and can't be clipped.
    var onStart: () -> Void = {}

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
    /// Start below this (outside its scroll), so nothing here renders Start.
    private var compactLayout: some View {
        VStack(spacing: 14) {
            familyTabs
                .modifier(FocusRing(focused: focusedRow == 0))

            pager
        }
    }

    // MARK: Regular layout (iPad / Mac / landscape) — family sidebar + detail pane

    /// Regular: families as a vertical sidebar list on the left with Start pinned
    /// at its bottom, the chosen family's options filling the detail pane on the
    /// right. Everything shown at once — no pager, no swipe — because the width is
    /// there. The sidebar column never scrolls (so Start is always visible); only
    /// the detail pane scrolls, if it ever must. Keyboard nav maps naturally:
    /// up/down move the family (row 0), left/right cycle within the focused row.
    private var regularLayout: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 16) {
                familySidebar
                    .modifier(FocusRing(focused: focusedRow == 0))
                Spacer(minLength: 12)
                startButton
            }
            .frame(width: 160)
            detailPaneStack
                .frame(maxWidth: .infinity)
        }
    }

    /// The Start button — a filled capsule. Placed by each layout (see `onStart`).
    var startButton: some View {
        Button(action: onStart) {
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

    /// The detail pane, sized to the TALLEST family so switching families never
    /// changes the modal height (Basic's three preset cards are taller than
    /// Grid/Hive's rows). All panes are laid on top of each other — the frame
    /// takes the max — and only the selected one is shown.
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

    private func familySidebarItem(_ family: BoardFamily) -> some View {
        let selected = settings.family == family
        return Button {
            withAnimation(.snappy) { settings.family = family }
            onFocusRow?(0)
        } label: {
            HStack(spacing: 10) {
                BoardGlyph(kind: .family(family), size: 24)
                Text(verbatim: family.label)
                    .font(.body.weight(selected ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.75))
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(selected ? 0.14 : 0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: family.label))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// The detail pane: the chosen family's options, filling the width. Reuses the
    /// same row builders as the compact pager (basic cards / difficulty chips /
    /// size chips / edges toggle), just laid out to fill the pane rather than a
    /// swipe page.
    @ViewBuilder private func detailPane(for family: BoardFamily) -> some View {
        switch family {
        case .basic:
            basicCards
        case .grid, .hive:
            VStack(spacing: 16) {
                densityChips(for: family)
                    .modifier(FocusRing(focused: focusedRow == 1))
                sizeChips(for: family)
                    .modifier(FocusRing(focused: focusedRow == 2))
                edgesToggle(for: family)
                    .modifier(FocusRing(focused: focusedRow == 3))
            }
        }
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

    /// All three pages side by side, offset to the selected one plus the live
    /// finger translation — the swipe is visible and interruptible, not a bare
    /// gesture that teleports the content.
    ///
    /// The slot is FIXED at the tallest page's height, so the popup never resizes
    /// as pages change (the tab row stays put); shorter pages top-align, keeping
    /// every family's difficulty row on the same line. The slot width comes from a
    /// dedicated full-width ruler, not from the sliding content — measuring the
    /// content itself would feed its own frame back into the layout.
    private var pager: some View {
        // The pages render only once the slot width has been measured, so the
        // FIRST real layout is already at the correct constrained width. Rendering
        // an unconstrained page as a pre-measure placeholder made the first open
        // lay out differently from a later return (ViewThatFits saw an infinite
        // width and never wrapped) — so before measuring, show only a zero-content
        // ruler; its full width sets `pagerWidth`, then the real pages appear.
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
        // Framed panels slightly narrower than the slot, so the neighbours' framed
        // edges peek in — the visible "there's more" cue. A gradient mask fades
        // just the outer edges so those peeking frames dissolve rather than being
        // hard-cut.
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

    /// Opaque across the middle, fading to clear over a thin strip at each edge —
    /// so a peeking neighbour panel dissolves out instead of being sliced. The fade
    /// is narrow (just the gap + a little), keeping the selected panel crisp.
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

    /// One page as a faintly-bordered panel — the frame is the swipability cue.
    /// Stretches to the fixed slot height (content top-aligned), so the peeking
    /// neighbours read as equal cards.
    private func pagePanel(for family: BoardFamily, width: CGFloat) -> some View {
        page(for: family)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .frame(width: width, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.primary.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.primary.opacity(0.10), lineWidth: 1))
            )
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: PageHeightsKey.self,
                        value: [family: geo.size.height])
                })
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

    private func familyTab(_ family: BoardFamily) -> some View {
        let selected = settings.family == family
        return Button {
            withAnimation(.snappy) { settings.family = family }
            onFocusRow?(0)
        } label: {
            // Hug the content: the hit area stays tight to the drawn tab, leaving
            // the space between tabs free to grab for the page swipe.
            VStack(spacing: 3) {
                BoardGlyph(kind: .family(family), size: 26)
                Text(verbatim: family.label)
                    .font(.caption.weight(selected ? .bold : .regular))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 7)
            .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.65))
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(selected ? 0.14 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: family.label))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: Pages

    @ViewBuilder private func page(for family: BoardFamily) -> some View {
        switch family {
        case .basic:
            basicCards
        case .grid, .hive:
            VStack(spacing: 12) {
                densityChips(for: family)
                    .modifier(FocusRing(focused: focusedRow == 1))
                sizeChips(for: family)
                    .modifier(FocusRing(focused: focusedRow == 2))
                edgesToggle(for: family)
                    .modifier(FocusRing(focused: focusedRow == 3))
            }
        }
    }

    // MARK: Shared rows

    /// The caption under a chip row: board facts (bold) on line 1, tagline
    /// (italic) on line 2. Each line has a FIXED height and shrinks to fit its
    /// WIDTH only (single line, `minimumScaleFactor`) — so a long value scales down
    /// horizontally instead of wrapping to a second line, and the block's height
    /// never changes between selections.
    func detailLine(detail: String, tagline: String) -> some View {
        VStack(spacing: 2) {
            captionText(detail, weight: .bold, opacity: 1)
            captionText(tagline, weight: .regular, opacity: 0.75, italic: true)
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: detail)
    }

    /// One caption line: single line, fixed height, shrinks to fit width only.
    private func captionText(
        _ text: String, weight: Font.Weight, opacity: Double, italic: Bool = false
    ) -> some View {
        Text(verbatim: text)
            .font(.body.weight(weight))
            .italic(italic)
            .foregroundStyle(.primary.opacity(opacity))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(height: Self.captionLineHeight)
    }

    /// Fixed height for one `.body` caption line, so shrinking a long value never
    /// changes the row's height.
    private static let captionLineHeight: CGFloat = 22
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

/// Wraps a control with the keyboard focus ring used across the picker rows.
struct FocusRing: ViewModifier {
    let focused: Bool
    func body(content: Content) -> some View {
        content
            // Always-present panel, recoloured on focus (never resizes).
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(focused ? 0.12 : 0))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.accentColor.opacity(focused ? 1 : 0), lineWidth: 2)))
    }
}
