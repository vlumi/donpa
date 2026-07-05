import DonpaCore
import SwiftUI

/// Create, rename, and delete the group catalog. Renaming keeps membership (groups
/// are referenced by id); deleting removes the group from every friend too. Reached
/// from the friends list; the per-friend membership picker lives in the detail sheet.
struct ManageGroupsView: View {
    @ObservedObject var friends: FriendsStore
    @ObservedObject var scoreboard: Scoreboard
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    /// The group being renamed (its detail row shows a text field), or nil.
    @State private var renamingID: String?
    @State private var renameText = ""
    /// The group whose members are expanded inline, or nil.
    @State private var expandedID: String?
    /// The group being compared head-to-head (vs its best per board), or nil.
    @State private var comparing: FriendGroup?

    var body: some View {
        chrome
            .sheet(item: $comparing) { group in
                HeadToHeadView(
                    scoreboard: scoreboard, opponentName: group.name,
                    result: RivalRanking.headToHead(
                        withGroup: friends.members(of: group.id), scoreboard: scoreboard))
            }
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                TextField(text: $newName) {
                    Text("New group", bundle: .module)
                }
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)
                Button(action: create) {
                    Text("Add", bundle: .module)
                }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if friends.groups.isEmpty {
                Text("No groups yet.", bundle: .module)
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                List {
                    ForEach(friends.groups) { group in
                        row(for: group)
                        if expandedID == group.id {
                            memberList(for: group)
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { friends.groups[$0].id }.forEach { friends.deleteGroup($0) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func row(for group: FriendGroup) -> some View {
        if renamingID == group.id {
            HStack(spacing: 8) {
                TextField(text: $renameText) { Text(group.name) }
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitRename(group) }
                Button {
                    commitRename(group)
                } label: {
                    Text("Save", bundle: .module)
                }
            }
        } else {
            HStack {
                Text(group.name)
                Spacer()
                // Tap the count to expand/collapse the member list.
                Button {
                    expandedID = (expandedID == group.id) ? nil : group.id
                } label: {
                    let count = friends.members(of: group.id).count
                    HStack(spacing: 4) {
                        Text("\(count)").font(.caption)
                        Image(systemName: expandedID == group.id ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                // Compare vs this group's best per board.
                Button {
                    comparing = group
                } label: {
                    Image(systemName: "chart.bar")
                }
                .buttonStyle(.borderless)
                .disabled(friends.members(of: group.id).isEmpty)
                Button {
                    renamingID = group.id
                    renameText = group.name
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
            }
            .contentShape(Rectangle())
        }
    }

    /// The friends in a group, shown inline under its row when expanded.
    @ViewBuilder private func memberList(for group: FriendGroup) -> some View {
        let members = friends.members(of: group.id)
        if members.isEmpty {
            Text("No members yet.", bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
                .padding(.leading, 16)
        } else {
            ForEach(members) { friend in
                Text(friend.displayName)
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.leading, 16)
            }
        }
    }

    private func create() {
        friends.createGroup(named: newName)
        newName = ""
    }

    private func commitRename(_ group: FriendGroup) {
        friends.renameGroup(group.id, to: renameText)
        renamingID = nil
    }

    @ViewBuilder private var chrome: some View {
        #if os(iOS)
        NavigationStack {
            content.padding(.horizontal, 8)
                .navigationTitle(Text("Groups", bundle: .module))
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
            Text("Groups", bundle: .module).font(.title2.bold())
            content.frame(minHeight: 220)
            Button {
                dismiss()
            } label: {
                Text("Done", bundle: .module)
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .frame(minWidth: 340, minHeight: 340)
        #endif
    }
}
