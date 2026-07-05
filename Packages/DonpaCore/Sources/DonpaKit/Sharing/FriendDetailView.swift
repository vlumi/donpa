import DonpaCore
import SwiftUI

/// A friend's detail: rename them locally (your alias, which survives their own
/// renames), tag them into groups, or remove them. Edits go straight to
/// `FriendsStore`; there's no Save button — the store persists on each change, and
/// Done just closes.
struct FriendDetailView: View {
    let friend: Friend
    @ObservedObject var friends: FriendsStore
    @Environment(\.dismiss) private var dismiss

    @State private var alias: String
    @State private var groupSelection: Set<String>
    @State private var confirmingRemove = false

    init(friend: Friend, friends: FriendsStore) {
        self.friend = friend
        self.friends = friends
        _alias = State(initialValue: friend.localAlias ?? "")
        _groupSelection = State(initialValue: Set(friend.groups))
    }

    var body: some View {
        chrome
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Their own name is fixed (it comes from their signed share); your alias
            // is the editable one.
            VStack(alignment: .leading, spacing: 4) {
                Text("Shared name", bundle: .module).font(.caption).foregroundStyle(.secondary)
                Text(friend.sharedName).font(.body)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Your name for them", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
                TextField(text: $alias) {
                    Text("Optional", bundle: .module)
                }
                .textFieldStyle(.roundedBorder)
                .onChangeCompat(of: alias) { friends.setAlias($0, for: friend.publicKey) }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Groups", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
                GroupPicker(friends: friends, selection: $groupSelection)
                    .onChangeCompat(of: groupSelection) {
                        friends.setGroups(Array($0), for: friend.publicKey)
                    }
            }

            Button(role: .destructive) {
                confirmingRemove = true
            } label: {
                Text("Remove rival", bundle: .module)
            }
            .padding(.top, 4)
        }
    }

    private func remove() {
        friends.delete(friend.publicKey)
        dismiss()
    }

    @ViewBuilder private var chrome: some View {
        #if os(iOS)
        NavigationStack {
            content.padding(20)
                .navigationTitle(Text(friend.displayName))
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
                .confirmationDialog(
                    Text("Remove \(friend.displayName)?", bundle: .module),
                    isPresented: $confirmingRemove, titleVisibility: .visible
                ) { removeButton }
        }
        #else
        VStack(spacing: 16) {
            Text(friend.displayName).font(.title2.bold())
            content
            Button {
                dismiss()
            } label: {
                Text("Done", bundle: .module)
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(minWidth: 340)
        .confirmationDialog(
            Text("Remove \(friend.displayName)?", bundle: .module),
            isPresented: $confirmingRemove, titleVisibility: .visible
        ) { removeButton }
        #endif
    }

    @ViewBuilder private var removeButton: some View {
        Button(role: .destructive, action: remove) {
            Text("Remove", bundle: .module)
        }
    }
}
