import DonpaCore
import SwiftUI

/// Edit a group's membership from the group side: a checklist of all rivals, tap to
/// add/remove them from this group. The per-rival group picker (in rival detail) still
/// works too — this is the faster "add several to one group" path. Changes persist
/// immediately via `FriendsStore.setMembership`.
struct GroupMembersView: View {
    let group: FriendGroup
    @ObservedObject var friends: FriendsStore
    @Environment(\.dismiss) private var dismiss

    /// Rivals A–Z, so a specific one is easy to find (matches the rivals list order).
    private var rivals: [Friend] {
        friends.friends.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    var body: some View {
        chrome
    }

    @ViewBuilder private var content: some View {
        if rivals.isEmpty {
            Text("No rivals to add yet.", bundle: .module)
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            List(rivals) { rival in
                let member = rival.groups.contains(group.id)
                Button {
                    friends.setMembership(!member, of: rival.publicKey, in: group.id)
                } label: {
                    HStack {
                        Image(systemName: member ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(member ? Color.accentColor : .secondary)
                        Text(rival.displayName)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var chrome: some View {
        #if os(iOS)
        NavigationStack {
            content
                .navigationTitle(Text(verbatim: group.name))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Done", bundle: .module)
                        }
                    }
                }
        }
        #else
        VStack(spacing: 12) {
            Text(verbatim: group.name).font(.title2.bold())
            content.frame(minHeight: 240)
            Button {
                dismiss()
            } label: {
                Text("Done", bundle: .module)
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .frame(minWidth: 320, minHeight: 340)
        #endif
    }
}
