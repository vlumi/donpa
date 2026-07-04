import DonpaCore
import SwiftUI

/// The tracked-friends list: everyone you've pinned via a share. Sorted most-recent
/// first (their latest share's `issuedAt`), each row showing the display name and a
/// one-line summary. Tap a row to rename (your local alias), edit groups, or remove.
/// Read-only over `FriendsStore` except through its methods — the display-merge
/// invariant means removing a friend just drops their data, nothing to reconcile.
struct FriendsListView: View {
    @ObservedObject var friends: FriendsStore
    @Environment(\.dismiss) private var dismiss

    /// The friend whose detail sheet is open (rename / groups / remove).
    @State private var editing: Friend?
    /// Whether the group-management sheet (create/rename/delete) is open.
    @State private var managingGroups = false

    /// Most-recent share first; ties broken by when you added them.
    private var ordered: [Friend] {
        friends.friends.sorted {
            ($0.lastIssuedAt, $0.addedAt) > ($1.lastIssuedAt, $1.addedAt)
        }
    }

    var body: some View {
        chrome
            .sheet(item: $editing) { friend in
                FriendDetailView(friend: friend, friends: friends)
            }
            .sheet(isPresented: $managingGroups) {
                ManageGroupsView(friends: friends)
            }
    }

    /// A friend's group names, resolved from their membership ids via the catalog.
    private func groupNames(for friend: Friend) -> [String] {
        friend.groups.compactMap { id in friends.groups.first { $0.id == id }?.name }
    }

    @ViewBuilder private var content: some View {
        if ordered.isEmpty {
            emptyState
        } else {
            List {
                ForEach(ordered) { friend in
                    Button {
                        editing = friend
                    } label: {
                        FriendRow(friend: friend, groupNames: groupNames(for: friend))
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    offsets.map { ordered[$0].publicKey }.forEach(friends.delete)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2")
                .font(.system(size: 48)).foregroundStyle(.secondary)
            Text("No friends yet.", bundle: .module).font(.headline)
            Text(
                "Add a friend by scanning their QR code or opening a share link.",
                bundle: .module
            )
            .font(.callout).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var chrome: some View {
        #if os(iOS)
        NavigationStack {
            content
                .navigationTitle(Text("Friends", bundle: .module))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            managingGroups = true
                        } label: {
                            Label {
                                Text("Manage groups", bundle: .module)
                            } icon: {
                                Image(systemName: "folder")
                            }
                        }
                    }
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
            HStack {
                Text("Friends", bundle: .module).font(.title2.bold())
                Spacer()
                Button {
                    managingGroups = true
                } label: {
                    Label {
                        Text("Manage groups", bundle: .module)
                    } icon: {
                        Image(systemName: "folder")
                    }
                }
            }
            content.frame(minHeight: 240)
            Button {
                dismiss()
            } label: {
                Text("Done", bundle: .module)
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .frame(minWidth: 360, minHeight: 360)
        #endif
    }
}

/// A friend's list row: display name (your alias wins), any group tags, and a compact
/// score summary (boards won · total wins).
private struct FriendRow: View {
    let friend: Friend
    /// The friend's group names, resolved from ids by the list (which holds the catalog).
    let groupNames: [String]

    private var boardsWon: Int { friend.scores.filter { $0.wins > 0 }.count }
    private var totalWins: Int { friend.scores.reduce(0) { $0 + $1.wins } }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(friend.displayName).font(.body.bold())
                // If a local alias is hiding their own name, show it faintly so you
                // can still tell who they call themselves.
                if friend.localAlias != nil {
                    Text(friend.sharedName).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("\(boardsWon) boards · \(totalWins) wins", bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
            if !groupNames.isEmpty {
                Text(groupNames.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
