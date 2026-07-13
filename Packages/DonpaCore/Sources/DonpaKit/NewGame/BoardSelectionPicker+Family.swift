import DonpaCore
import SwiftUI

/// The family selectors' item builders (pager tab + sidebar row), split from
/// the picker for the file/type-length budgets. Both carry the same badge
/// stack: save dot, padlock, spoken save/lock values.
extension BoardSelectionPicker {
    func familySidebarItem(_ family: BoardFamily) -> some View {
        let selected = settings.family == family
        return Button {
            withAnimation(FamilySwitch.animation) { settings.family = family }
            lockedHint = nil  // don't carry a stale teaser onto the new page
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
        .modifier(SaveDot(show: index.familyHasSave(family)))
        .modifier(LockBadge(locked: !gates.family(family)))
        .accessibilityLabel(Text(verbatim: family.label))
        .modifier(SaveValue(hasSave: index.familyHasSave(family)))
        .modifier(LockValue(locked: !gates.family(family), requirement: .winAnySquare))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    func familyTab(_ family: BoardFamily) -> some View {
        let selected = settings.family == family
        return Button {
            withAnimation(FamilySwitch.animation) { settings.family = family }
            lockedHint = nil  // don't carry a stale teaser onto the new page
            onFocusRow?(0)
        } label: {
            VStack(spacing: 3) {
                BoardGlyph(kind: .family(family), size: 26)
                Text(verbatim: family.label)
                    .font(.caption.weight(selected ? .bold : .regular))
                    .lineLimit(1)  // keep e.g. "グリッド" on one line (don't wrap → taller tab)
                    .minimumScaleFactor(0.6)  // a long label shrinks rather than widening its tab
            }
            // Equal-width tabs: every tab fills the same share of the row, so neither
            // the differing label lengths nor the regular↔bold selection swap can
            // change a tab's width — that width change was the row "wobble".
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
        .modifier(SaveDot(show: index.familyHasSave(family)))
        .modifier(LockBadge(locked: !gates.family(family)))
        .accessibilityLabel(Text(verbatim: family.label))
        .modifier(SaveValue(hasSave: index.familyHasSave(family)))
        .modifier(LockValue(locked: !gates.family(family), requirement: .winAnySquare))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
