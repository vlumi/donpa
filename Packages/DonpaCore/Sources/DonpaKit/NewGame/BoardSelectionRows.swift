import DonpaCore
import SwiftUI

/// The per-family row builders for `BoardSelectionPicker`: the Basic preset
/// cards, the Grid/Hive size-chip row, and the Flat/Round edges glyph toggle.
/// Split from the picker (which keeps the pager + tabs) for the type-length cap.
extension BoardSelectionPicker {
    // MARK: Basic preset cards (row 1)

    /// The Basic page's own layout: three big preset cards stacked vertically,
    /// always all visible, each carrying its board facts and tagline inside — no
    /// drum to scroll. Keyboard row 1 (←/→ cycles the preset, same as the drums).
    var basicCards: some View {
        VStack(spacing: 8) {
            ForEach(BasicPreset.allCases, id: \.self) { preset in
                basicCard(preset)
            }
        }
        .modifier(FocusRing(focused: focusedRow == 1))
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
            .padding(.vertical, 14)
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
        .accessibilityLabel(Text(verbatim: "\(preset.label) — \(preset.detail)"))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: Size chips (row 2)

    var sizeChips: some View {
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

    var edgesToggle: some View {
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
}
