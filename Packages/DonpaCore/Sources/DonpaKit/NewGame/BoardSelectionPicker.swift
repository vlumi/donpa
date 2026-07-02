import DonpaCore
import SwiftUI

/// The board-config chooser: three paged **families** (Basic / Grid / Hive) under
/// a glyph tab strip. Basic shows the preset carousel; Grid and Hive share one
/// page layout — a difficulty carousel, a size-chip row, and the Flat/Round edges
/// glyph toggle. Binds directly to `Settings` — the pending choice; the host
/// decides when to start a game.
///
/// Graphical by design: the family is its tab glyph, edges are two equal glyph
/// pictures (framed map ↔ globe), difficulty is the rank insignia. The pages sit
/// side by side and SLIDE — the content tracks a drag (finger or mouse),
/// rubber-bands at the ends, and snaps a page over on release; a tab tap slides
/// the same way, so both platforms share one behaviour. The drum rows keep their
/// own horizontal scrolling. On macOS it's also keyboard-drivable — up/down move
/// between rows, left/right cycle within the focused row (row 0 = the tabs).
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
        VStack(spacing: 0) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 0)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: PagerWidthKey.self, value: geo.size.width)
                    })
            if pagerWidth > 0 {
                slidingPages
            } else {
                page(for: settings.family)  // pre-measure frame; replaced next pass
            }
        }
        .onPreferenceChange(PagerWidthKey.self) { width in
            guard width > 0 else { return }  // never regress to the fallback branch
            pagerWidth = width
        }
    }

    private var slidingPages: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(BoardFamily.allCases) { family in
                page(for: family)
                    .frame(width: pagerWidth, alignment: .top)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: PageHeightsKey.self,
                                value: [family: geo.size.height])
                        })
            }
        }
        .offset(x: -CGFloat(selectedIndex) * pagerWidth + rubberBanded(pagerDrag))
        .frame(
            width: pagerWidth, height: pageHeights.values.max(), alignment: .topLeading
        )
        .clipped()
        .contentShape(Rectangle())
        .gesture(pagerGesture)
        .onPreferenceChange(PageHeightsKey.self) { heights in
            pageHeights.merge(heights) { _, new in new }
        }
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
        HStack(spacing: 6) {
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
            VStack(spacing: 3) {
                BoardGlyph(kind: .family(family), size: 26)
                Text(verbatim: family.label)
                    .font(.caption.weight(selected ? .bold : .regular))
            }
            .frame(maxWidth: .infinity)
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
            // Difficulty is row 1, lining up with Grid/Hive's difficulty row.
            carouselRow(
                (family, 1),
                labels: BasicPreset.allCases.map(\.label),
                index: presetIndex,
                caption: (settings.basicPreset.detail, settings.basicPreset.tagline))
        case .grid, .hive:
            VStack(spacing: 12) {
                carouselRow(
                    (family, 1),
                    labels: Density.allCases.map(\.label),
                    index: densityIndex,
                    // Hive is denser per tier; show the number the board will use.
                    caption: (
                        settings.density.detail(hex: family == .hive),
                        settings.density.tagline
                    ),
                    symbol: { i in
                        let all = Density.allCases
                        return all.indices.contains(i) ? DensityInsignia.markImage(all[i]) : nil
                    })
                sizeChips
                    .modifier(FocusRing(focused: focusedRow == 2))
                edgesToggle
                    .modifier(FocusRing(focused: focusedRow == 3))
            }
        }
    }

    // MARK: Size chips (row 2)

    private var sizeChips: some View {
        VStack(spacing: 6) {
            // All seven chips in one row when there's room; two rows when not.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { chips(BoardSize.allCases) }
                VStack(spacing: 6) {
                    HStack(spacing: 6) { chips(Array(BoardSize.allCases.prefix(4))) }
                    HStack(spacing: 6) { chips(Array(BoardSize.allCases.dropFirst(4))) }
                }
            }
            detailLine(
                detail: settings.boardSize.detail, tagline: settings.boardSize.tagline)
        }
    }

    @ViewBuilder private func chips(_ sizes: [BoardSize]) -> some View {
        ForEach(sizes, id: \.self) { size in
            sizeChip(size)
        }
    }

    private func sizeChip(_ size: BoardSize) -> some View {
        let selected = settings.boardSize == size
        return Button {
            settings.boardSize = size
            onFocusRow?(2)
        } label: {
            Text(verbatim: size.label)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(
                    Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(size.label) — \(size.detail)"))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: Edges glyph toggle (row 3)

    private var edgesToggle: some View {
        HStack(spacing: 10) {
            ForEach(BoardEdges.allCases) { edges in
                edgesButton(edges)
            }
        }
    }

    private func edgesButton(_ edges: BoardEdges) -> some View {
        let selected = settings.edges == edges
        return Button {
            settings.edges = edges
            onFocusRow?(3)
        } label: {
            HStack(spacing: 8) {
                BoardGlyph(kind: .edges(edges), size: 24)
                Text(verbatim: edges.label).font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.65))
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(selected ? 0.14 : 0))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                selected
                                    ? Color.accentColor.opacity(0.6)
                                    : Color.primary.opacity(0.15)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: edges.label))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: Shared rows

    /// A carousel drum plus the detail/tagline line for its selected card. `slot`
    /// is the drum's place in the pager: its page family + keyboard row.
    private func carouselRow(
        _ slot: (family: BoardFamily, row: Int), labels: [String], index: Binding<Int>,
        caption: (detail: String, tagline: String), symbol: ((Int) -> Image?)? = nil
    ) -> some View {
        VStack(spacing: 4) {
            CarouselPicker(
                labels: labels, selection: index, focused: focusedRow == slot.row,
                symbol: symbol,
                onInteract: { onFocusRow?(slot.row) }
            )
            // Identity per family+row: a family switch builds a fresh carousel
            // centred on its selection (no stale scroll offset), and in the pager —
            // where every page is alive at once — each drum keeps its own identity.
            // (The Grid and Hive drums previously shared one `.id(labels)`, two
            // live views with the same explicit identity.)
            .id("\(slot.family.rawValue).row\(slot.row)")
            detailLine(detail: caption.detail, tagline: caption.tagline)
        }
    }

    private func detailLine(detail: String, tagline: String) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: detail).fontWeight(.bold).foregroundStyle(.primary)
            Text(verbatim: "·").foregroundStyle(.secondary)
            Text(verbatim: tagline).italic().foregroundStyle(.primary.opacity(0.75))
        }
        .font(.body)
        // Wrap rather than shrink, so a longer line keeps the same font size.
        .lineLimit(2)
        .multilineTextAlignment(.center)
        // Fixed width so the swapping content doesn't reflow while the drum animates.
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: detail)
    }

    // MARK: Enum ↔ index bindings (the carousel works in index space)

    private var presetIndex: Binding<Int> {
        enumIndex(\.basicPreset, all: BasicPreset.allCases)
    }
    private var densityIndex: Binding<Int> {
        enumIndex(\.density, all: Density.allCases)
    }

    /// A `Binding<Int>` over a `Settings` enum, mapping case↔index in `allCases`.
    /// Out-of-range writes are ignored.
    private func enumIndex<T: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<Settings, T>, all: [T]
    ) -> Binding<Int> {
        Binding(
            get: { all.firstIndex(of: settings[keyPath: keyPath]) ?? 0 },
            set: { i in
                guard all.indices.contains(i) else { return }
                settings[keyPath: keyPath] = all[i]
            })
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
private struct FocusRing: ViewModifier {
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
