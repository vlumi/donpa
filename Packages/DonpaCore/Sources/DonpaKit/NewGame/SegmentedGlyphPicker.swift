import SwiftUI

/// A segmented control whose segments carry a hand-drawn `BoardGlyph` (and an
/// optional label) rather than plain text — the shared look for the few-item board
/// axes (board family, Flat/Round edges) on BOTH the New Game modal and the
/// scoreboard filters, so the two screens read as one vocabulary.
///
/// Styled like a native segmented picker: the segments connect inside a single
/// rounded-outer container with square dividers between them (no rounded edges
/// mid-row), the selected one filled with the accent. Non-wrapping by design — for
/// the wrapping chip rows (difficulty, size) the picker stays a chip grid.
struct SegmentedGlyphPicker<Value: Hashable & Identifiable>: View {
    let values: [Value]
    @Binding var selection: Value
    /// The glyph drawn in each segment.
    let glyph: (Value) -> BoardGlyph.Kind
    /// The segment's label. Return "" to draw the glyph alone.
    let label: (Value) -> String
    /// Called after a segment is chosen (e.g. to collapse an open detail).
    var onChange: (() -> Void)?
    /// Whether a segment should carry a small corner badge (the New Game modal uses
    /// this for the in-progress-save dot). Defaults to none, so other callers (the
    /// scoreboard filters) render unbadged.
    var badge: (Value) -> Bool = { _ in false }

    /// Outer corner radius; inner segment splits are square so the row reads as one
    /// connected control.
    private static var cornerRadius: CGFloat { 10 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(values.enumerated()), id: \.element.id) { index, value in
                segment(value)
                if index != values.count - 1 { divider }
            }
        }
        // Hug the segments' height — the divider fills the row, but the row must NOT
        // grow into vertical slack a parent offers (the pager stretches its page to
        // the tallest family, which otherwise made this toggle tall + dead to touch).
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .fill(Color.primary.opacity(0.08))
        )
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }

    private func segment(_ value: Value) -> some View {
        let selected = selection == value
        let text = label(value)
        return Button {
            guard !selected else { return }
            selection = value
            onChange?()
        } label: {
            HStack(spacing: 6) {
                BoardGlyph(kind: glyph(value), size: 20)
                if !text.isEmpty {
                    Text(verbatim: text)
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        // Shrink to fit rather than truncate/wrap: a longer localized
                        // label (e.g. FI "Ruudukko") stays whole on a narrow segment.
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .foregroundStyle(selected ? Color.white : Color.primary)
            // Selected segment: an inset accent fill that keeps the outer corner
            // rounding (the container clips it) but reads flat against its neighbours.
            .background(selected ? Color.accentColor : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The control clips to its rounded container, so the dot insets into the
        // corner rather than overhanging (which would get sliced off).
        .modifier(SaveDot(show: badge(value), onAccent: selected, inset: true))
        .accessibilityLabel(Text(verbatim: text.isEmpty ? "\(value)" : text))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// A hairline between segments — hidden next to the selected one, whose fill
    /// already separates it.
    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }
}
