import DonpaCore
import SwiftUI

/// The rival-scope control — who the per-config comparison ranks you against
/// (all friends or one group). An extension so it doesn't count against
/// `ScoreboardView`'s type-body-length budget.
extension ScoreboardView {
    @ViewBuilder var rivalScopeControl: some View {
        HStack(spacing: 8) {
            Text("Compare with", bundle: .module).font(.caption).foregroundStyle(.secondary)
            Menu {
                Button {
                    rivalGroupID = nil
                } label: {
                    Text("All rivals", bundle: .module)
                }
                ForEach(friends.groups) { group in
                    Button {
                        rivalGroupID = group.id
                    } label: {
                        Text(group.name)
                    }
                }
            } label: {
                Text(rivalScopeLabel).font(.caption.bold())
            }
            .modifier(zoneRing(.rivals))
            Spacer()
            if let onMessHall {
                Button(action: onMessHall) {
                    Text("Manage rivals", bundle: .module).font(.caption)
                }
                .modifier(zoneRing(.manage))
            }
        }
        .padding(.horizontal, Self.rowInset)
    }

    private var rivalScopeLabel: String {
        guard let rivalGroupID, let group = friends.groups.first(where: { $0.id == rivalGroupID })
        else {
            return String(localized: "All rivals", bundle: .module)
        }
        return group.name
    }
}
