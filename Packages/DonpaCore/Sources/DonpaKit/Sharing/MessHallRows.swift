import DonpaCore
import SwiftUI

/// The Mess hall's shared row scaffolding (compare-body + edit-pencil rows,
/// tab empty states) — split from MessHallView for the file-length budget.
extension MessHallView {
    /// A list row whose body taps to compare, with a trailing pencil to edit. Compare
    /// can be disabled (e.g. an empty group has nothing to compare).
    @ViewBuilder func rowButton<Content: View>(
        compare: @escaping () -> Void, edit: @escaping () -> Void,
        compareDisabled: Bool = false, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Button(action: compare) { content().contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .disabled(compareDisabled)
            Button(action: edit) {
                Image(systemName: "pencil").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Edit", bundle: .module))
        }
    }

    func emptyState(
        icon: String, title: LocalizedStringKey, detail: LocalizedStringKey
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 48)).foregroundStyle(.secondary)
            Text(title, bundle: .module).font(.headline)
            Text(detail, bundle: .module)
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
