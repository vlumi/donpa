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

    /// Live drag offset while swiping the pager; snaps back with the same
    /// spring the page change uses, so release always lands smoothly.
    @GestureState(resetTransaction: Transaction(animation: .snappy))
    private var pagerDrag: CGFloat = 0
    /// The pager's slot width (one page), measured from layout.
    @State private var pagerWidth: CGFloat = 0
    /// Measured natural height per page; the slot is fixed at the tallest one.
    @State private var pageHeights: [BoardFamily: CGFloat] = [:]

    var body: some View {
        VStack(spacing: 14) {
            familyTabs
                .modifier(FocusRing(focused: focusedRow == 0))

            pager
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

    /// The caption under a chip row: board facts (bold) + the playful tagline
    /// (italic). One line when it fits (a roomy window, e.g. macOS), stacked to two
    /// lines when it wouldn't — never shrinking the text or truncating. Both the
    /// one- and two-line forms are reserved the same TWO-line height, so the row's
    /// height is constant and doesn't reflow as the selection changes.
    func detailLine(detail: String, tagline: String) -> some View {
        let facts = Text(verbatim: detail).fontWeight(.bold).foregroundStyle(.primary)
        let flavour = Text(verbatim: tagline).italic().foregroundStyle(.primary.opacity(0.75))
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                facts
                Text(verbatim: "·").foregroundStyle(.secondary)
                flavour
            }
            VStack(spacing: 2) {
                facts; flavour
            }
        }
        .font(.body)
        .lineLimit(1)
        // A gentle shrink as the last resort so the longest tagline
        // ("Abandon all hope, ye who enter") fits its line on a phone rather than
        // truncating; short captions render at full size.
        .minimumScaleFactor(0.8)
        .multilineTextAlignment(.center)
        // Reserve two lines of `.body` (~22pt each + 2pt spacing) always, so
        // switching between a one-line and a two-line caption never jumps the row.
        .frame(maxWidth: .infinity, minHeight: 46)
        .animation(.snappy, value: detail)
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
