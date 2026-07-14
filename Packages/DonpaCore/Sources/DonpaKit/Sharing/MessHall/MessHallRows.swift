import DonpaCore
import SwiftUI

struct CompareEditRow<Content: View>: View {
    let compare: () -> Void
    let edit: () -> Void
    var compareDisabled = false
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) {
            Button(action: compare) { content.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .disabled(compareDisabled)
            Button(action: edit) {
                Image(systemName: "pencil").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Edit", bundle: .module))
        }
    }
}

struct ListEmptyState: View {
    let icon: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
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
