import DonpaCore
import SwiftUI

/// The scoreboard's rival-scope control — who the per-config comparison ranks you
/// against (all friends or one group). Split into an extension so it doesn't count
/// against `ScoreboardView`'s type-body-length budget (mirrors `ScoreboardToolbar`).
extension ScoreboardView {
    /// Shown only when you have friends; the group options appear only when you have
    /// groups. Drives `rivalGroupID`, which `leafRows` reads to pick the rivals set.
    @ViewBuilder var rivalScopeControl: some View {
        HStack(spacing: 8) {
            Text("Compare with", bundle: .module).font(.caption).foregroundStyle(.secondary)
            Menu {
                Button {
                    rivalGroupID = nil
                } label: {
                    Text("All friends", bundle: .module)
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
            Spacer()
        }
        .padding(.horizontal, Self.rowInset)
    }

    private var rivalScopeLabel: String {
        guard let rivalGroupID, let group = friends.groups.first(where: { $0.id == rivalGroupID })
        else {
            return String(localized: "All friends", bundle: .module)
        }
        return group.name
    }
}
