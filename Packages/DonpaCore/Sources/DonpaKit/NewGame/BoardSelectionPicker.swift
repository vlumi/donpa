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
    /// Start the game with the current selection. The picker owns the Start button
    /// so each layout can place it (sidebar: below its column; pager: the host pins
    /// it full-width below).
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
    /// Start below this, so nothing here renders it.
    private var compactLayout: some View {
        VStack(spacing: 14) {
            familyTabs
                .modifier(FocusRing(focused: focusedRow == 0))

            pager
        }
    }

    // MARK: Regular layout (iPad / Mac / landscape) — family sidebar + detail pane

    /// Regular: a family sidebar (with Start below it) beside the detail pane. Both
    /// columns hug their content; the card hugs the taller of the two.
    private var regularLayout: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 16) {
                familySidebar
                    .modifier(FocusRing(focused: focusedRow == 0))
                startButton
            }
            .frame(width: 160)
            detailPaneStack
                .frame(maxWidth: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)  // hug height; don't fill the window
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

    /// The detail pane: the chosen family's options, filling the width. Same content
    /// as a pager page (`familyContent`) — the sidebar just packs the Grid/Hive rows
    /// a touch tighter, since it's the short-wide layout.
    private func detailPane(for family: BoardFamily) -> some View {
        familyContent(for: family, gridHiveSpacing: 8)
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
            .frame(maxHeight: .infinity, alignment: .top)
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
                    .lineLimit(1)  // keep e.g. "グリッド" on one line (don't wrap → taller tab)
                    .fixedSize()
            }
            .padding(.horizontal, 16)
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

    private func page(for family: BoardFamily) -> some View {
        familyContent(for: family, gridHiveSpacing: 12)
    }

    /// A family's option rows, shared by the pager page and the sidebar detail pane.
    /// Basic is its three preset cards; Grid/Hive are the difficulty / size / edges
    /// rows, stacked with the caller's spacing (the pager breathes a little more,
    /// the short-wide sidebar packs tighter).
    @ViewBuilder private func familyContent(
        for family: BoardFamily, gridHiveSpacing: CGFloat
    ) -> some View {
        switch family {
        case .basic:
            basicCards
        case .grid, .hive:
            VStack(spacing: gridHiveSpacing) {
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

    /// The caption under a chip row: board facts (bold) then tagline (italic). Each
    /// line is fixed-height and shrinks to fit its width, so a long value scales
    /// down instead of wrapping and the block's height never changes.
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
