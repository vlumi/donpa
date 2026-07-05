import DonpaCore
import SwiftUI

/// The tracked-friends list: everyone you've pinned via a share. Sorted most-recent
/// first (their latest share's `issuedAt`), each row showing the display name and a
/// one-line summary. Tap a row to rename (your local alias), edit groups, or remove.
/// Read-only over `FriendsStore` except through its methods — the display-merge
/// invariant means removing a friend just drops their data, nothing to reconcile.
struct FriendsListView: View {
    @ObservedObject var friends: FriendsStore
    @ObservedObject var scoreboard: Scoreboard
    @Environment(\.dismiss) private var dismiss

    /// The friend whose detail sheet is open (rename / groups / remove).
    @State private var editing: Friend?
    /// The friend being compared head-to-head, or nil.
    @State private var comparing: Friend?
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
            .sheet(item: $comparing) { friend in
                HeadToHeadView(
                    scoreboard: scoreboard, opponentName: friend.displayName,
                    result: RivalRanking.headToHead(with: friend, scoreboard: scoreboard))
            }
            .sheet(isPresented: $managingGroups) {
                ManageGroupsView(friends: friends, scoreboard: scoreboard)
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
                    // Compare is a secondary action (tapping the row opens detail).
                    .swipeActions(edge: .leading) {
                        Button {
                            comparing = friend
                        } label: {
                            Label {
                                Text("Compare", bundle: .module)
                            } icon: {
                                Image(systemName: "chart.bar")
                            }
                        }
                        .tint(.accentColor)
                    }
                    .contextMenu {
                        Button {
                            comparing = friend
                        } label: {
                            Label {
                                Text("Compare", bundle: .module)
                            } icon: {
                                Image(systemName: "chart.bar")
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { ordered[$0].publicKey }.forEach { friends.delete($0) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2")
                .font(.system(size: 48)).foregroundStyle(.secondary)
            Text("No rivals yet.", bundle: .module).font(.headline)
            Text(
                "Add a rival's scores by scanning their QR code or opening a share link.",
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
                .navigationTitle(Text("Rivals", bundle: .module))
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
                Text("Rivals", bundle: .module).font(.title2.bold())
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
        HStack(alignment: .top, spacing: 12) {
            // Leading: who + when (the identity block).
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName).font(.body.bold())
                    .lineLimit(1).minimumScaleFactor(0.7)
                // If a local alias is hiding their own name, show it faintly so you
                // can still tell who they call themselves.
                if friend.localAlias != nil {
                    Text(friend.sharedName).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                // Their share's own timestamp — makes plain these are a SNAPSHOT that
                // only changes when they re-share, not something that updates itself.
                Text(
                    "Updated \(friend.lastIssuedAt.formatted(date: .abbreviated, time: .omitted))",
                    bundle: .module
                )
                .font(.caption2).foregroundStyle(.secondary)
                if !groupNames.isEmpty {
                    Text(groupNames.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            // Trailing: the score summary, right-aligned so the row fills its width.
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(totalWins) wins", bundle: .module)
                    .font(.subheadline.bold())
                Text("\(boardsWon) boards", bundle: .module)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}
