import DonpaCore
import SwiftUI

/// The per-family row builders for `BoardSelectionPicker`: the Basic preset
/// cards, the Grid/Hive size-chip row, and the Flat/Round edges glyph toggle.
/// Split from the picker (which keeps the pager + tabs) for the type-length cap.
extension BoardSelectionPicker {
    // MARK: Basic preset cards (row 1)

    /// The Basic page's own layout: three big preset cards stacked vertically,
    /// always all visible, each carrying its board facts and tagline inside — no
    /// Keyboard row 0 for Basic — ←/→ cycles the preset (family is ⌘1-3, not a row).
    var basicCards: some View {
        VStack(spacing: 6) {
            ForEach(BasicPreset.allCases, id: \.self) { preset in
                basicCard(preset)
            }
        }
        .modifier(FocusRing(focused: focusedRow == 0))
    }

    private func basicCard(_ preset: BasicPreset) -> some View {
        let selected = settings.basicPreset == preset
        return Button {
            settings.basicPreset = preset
            onFocusRow?(1)
        } label: {
            VStack(spacing: 2) {
                Text(verbatim: preset.label)
                    .font(.headline)
                Text(verbatim: preset.detail)
                    .font(.subheadline.weight(.medium))
                Text(verbatim: preset.tagline)
                    .font(.subheadline)
                    .italic()
                    .opacity(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.75))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(selected ? 0.14 : 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                selected
                                    ? Color.accentColor.opacity(0.6)
                                    : Color.primary.opacity(0.12)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(SaveDot(show: index.presetHasSave(preset)))
        .accessibilityLabel(Text(verbatim: "\(preset.label) — \(preset.detail)"))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: Difficulty chips (row 1)

    /// The difficulty as five always-visible rank-insignia chips — NOT a drum: a
    /// horizontally-scrolling row inside a horizontally-swiped pager is two
    /// gestures fighting over the same axis. The selected tier's name, honest mine
    /// percentage (Hive runs denser), and tagline sit in the caption below.
    func densityChips(for family: BoardFamily) -> some View {
        let densityPath = Settings.densityPath(family)
        let selected = settings[keyPath: densityPath]
        return VStack(spacing: 6) {
            // All five chips in one row when there's room; 3 + 2 when not (matching
            // the size chips' wrap).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { densityRow(Density.allCases, densityPath) }
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        densityRow(Array(Density.allCases.prefix(3)), densityPath)
                    }
                    HStack(spacing: 8) {
                        densityRow(Array(Density.allCases.dropFirst(3)), densityPath)
                    }
                }
            }
            detailLine(
                detail: "\(selected.label) · \(selected.detail(hex: family == .hive))",
                tagline: selected.tagline)
        }
    }

    @ViewBuilder private func densityRow(
        _ densities: [Density], _ densityPath: ReferenceWritableKeyPath<Settings, Density>
    ) -> some View {
        ForEach(densities, id: \.self) { density in
            densityChip(density, densityPath)
        }
    }

    private func densityChip(
        _ density: Density, _ densityPath: ReferenceWritableKeyPath<Settings, Density>
    ) -> some View {
        let selected = settings[keyPath: densityPath] == density
        // Filtered by the choices ABOVE it (family + current size), so the dot only
        // lights when a save exists reachable down THIS path.
        let hasSave = index.densityHasSave(
            density, family: settings.family, size: settings[keyPath: Settings.sizePath(settings.family)])
        return Button {
            settings[keyPath: densityPath] = density
            onFocusRow?(1)
        } label: {
            DensityInsignia.markImage(density)
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 22)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(
                    Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .modifier(SaveDot(show: hasSave))
        .accessibilityLabel(Text(verbatim: density.label))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: Size chips (row 2)

    func sizeChips(for family: BoardFamily) -> some View {
        let sizePath = Settings.sizePath(family)
        return VStack(spacing: 6) {
            // All seven chips in one row when there's room; two rows when not.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { chips(BoardSize.allCases, sizePath) }
                VStack(spacing: 6) {
                    HStack(spacing: 6) { chips(Array(BoardSize.allCases.prefix(4)), sizePath) }
                    HStack(spacing: 6) { chips(Array(BoardSize.allCases.dropFirst(4)), sizePath) }
                }
            }
            detailLine(
                detail: settings[keyPath: sizePath].detail,
                tagline: settings[keyPath: sizePath].tagline)
        }
    }

    @ViewBuilder private func chips(
        _ sizes: [BoardSize], _ sizePath: ReferenceWritableKeyPath<Settings, BoardSize>
    ) -> some View {
        ForEach(sizes, id: \.self) { size in
            sizeChip(size, sizePath)
        }
    }

    private func sizeChip(
        _ size: BoardSize, _ sizePath: ReferenceWritableKeyPath<Settings, BoardSize>
    ) -> some View {
        let selected = settings[keyPath: sizePath] == size
        // Size sits just under family in the hierarchy, so it's filtered by family only.
        let hasSave = index.sizeHasSave(size, family: settings.family)
        return Button {
            settings[keyPath: sizePath] = size
            onFocusRow?(2)
        } label: {
            Text(verbatim: size.label)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                // Match the difficulty chips' pill size (same 22pt content height +
                // 8pt padding), so the size row never reads as bigger than it.
                .frame(height: 22)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(
                    Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .modifier(SaveDot(show: hasSave))
        .accessibilityLabel(Text(verbatim: "\(size.label) — \(size.detail)"))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: Edges glyph toggle (row 3)

    // (SaveDot lives at file scope below — the shared corner-badge modifier.)

    func edgesToggle(for family: BoardFamily) -> some View {
        let edgesPath = Settings.edgesPath(family)
        let size = settings[keyPath: Settings.sizePath(family)]
        let density = settings[keyPath: Settings.densityPath(family)]
        return SegmentedGlyphPicker(
            values: BoardEdges.allCases,
            selection: Binding(
                get: { settings[keyPath: edgesPath] },
                set: { settings[keyPath: edgesPath] = $0 }),
            glyph: { .edges($0) }, label: { $0.label },
            onChange: { onFocusRow?(3) },
            // Edges is the leaf: filtered by the full path above (family + size + density).
            badge: { index.edgesHasSave($0, family: family, size: size, density: density) })
    }
}

/// A small badge marking a selector chip whose drill-down path holds an in-progress
/// save, so following lit chips down (family → size → density → edges) always lands on
/// a real saved board. Non-interactive, tucked in the chip's top-trailing corner; it
/// rides an overlay so it never changes the chip's layout. Hidden when `show` is false.
struct SaveDot: ViewModifier {
    let show: Bool
    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if show {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
                    // Nudge onto the chip's shoulder rather than floating off it.
                    .offset(x: 3, y: -3)
                    .allowsHitTesting(false)
                    // The chip's own a11y label already conveys the config; the dot is
                    // a redundant visual cue, so it stays out of the a11y tree.
                    .accessibilityHidden(true)
            }
        }
    }
}
