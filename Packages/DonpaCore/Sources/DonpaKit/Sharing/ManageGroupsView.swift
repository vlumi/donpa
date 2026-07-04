import DonpaCore
import SwiftUI

/// Create, rename, and delete the group catalog. Renaming keeps membership (groups
/// are referenced by id); deleting removes the group from every friend too. Reached
/// from the friends list; the per-friend membership picker lives in the detail sheet.
struct ManageGroupsView: View {
    @ObservedObject var friends: FriendsStore
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    /// The group being renamed (its detail row shows a text field), or nil.
    @State private var renamingID: String?
    @State private var renameText = ""

    var body: some View {
        chrome
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
                    }
                    .onDelete { $0.map { friends.groups[$0].id }.forEach(friends.deleteGroup) }
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
                Text("\(friends.members(of: group.id).count)")
                    .font(.caption).foregroundStyle(.secondary)
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
