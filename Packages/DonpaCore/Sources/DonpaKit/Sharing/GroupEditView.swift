import DonpaCore
import SwiftUI

/// Everything for one group in a single view — rename, add/remove members (a rival
/// checklist), and delete — no nested popups. Opened by the pencil on a group row, and
/// automatically right after creating a group so you can name it and add rivals in one
/// flow. All edits persist immediately via `FriendsStore`.
struct GroupEditView: View {
    let group: FriendGroup
    @ObservedObject var friends: FriendsStore
    @Environment(\.dismiss) private var dismiss
    #if os(macOS)
    /// The keyboard-focused member checkbox (arrow navigation).
    @State private var keyIndex: Int?
    #endif

    @State private var name: String
    @State private var confirmingDelete = false

    init(group: FriendGroup, friends: FriendsStore) {
        self.group = group
        self.friends = friends
        _name = State(initialValue: group.name)
    }

    /// Rivals A–Z (matches the rivals list order), so a specific one is easy to find.
    private var rivals: [Friend] {
        friends.friends.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    var body: some View {
        chrome
            .escDismisses { dismiss() }
            .confirmationDialog(
                Text("Delete “\(group.name)”?", bundle: .module),
                isPresented: $confirmingDelete, titleVisibility: .visible
            ) {
                Button(role: .destructive) {
                    friends.deleteGroup(group.id)
                    dismiss()
                } label: {
                    Text("Delete squad", bundle: .module)
                }
                Button(role: .cancel) {
                } label: {
                    Text("Cancel", bundle: .module)
                }
            } message: {
                Text("This removes the squad. Your rivals and their scores stay.", bundle: .module)
            }
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Squad name", bundle: .module).font(.caption).foregroundStyle(.secondary)
                TextField(text: $name) { Text("Squad name", bundle: .module) }
                    .textFieldStyle(.roundedBorder)
                    // Persist on each edit (blank is ignored by the store).
                    .onChangeCompat(of: name) { friends.renameGroup(group.id, to: $0) }
            }

            Text("Members", bundle: .module).font(.caption).foregroundStyle(.secondary)
            memberList

            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Text("Delete squad", bundle: .module)
            }
            .padding(.top, 4)
        }
    }

    private func memberRing(_ index: Int) -> FocusRing {
        #if os(macOS)
        return FocusRing(focused: keyIndex == index, inset: 2)
        #else
        return FocusRing(focused: false, inset: 0)
        #endif
    }

    #if os(macOS)
    private func handleKey(_ key: KeyCatcher.Key) {
        switch key {
        case .down, .tab: moveFocus(1)
        case .up, .backTab: moveFocus(-1)
        case .enter:
            guard let index = keyIndex, rivals.indices.contains(index) else { return }
            let rival = rivals[index]
            let member = rival.groups.contains(group.id)
            friends.setMembership(!member, of: rival.publicKey, in: group.id)
        default: break
        }
    }

    private func moveFocus(_ delta: Int) {
        guard !rivals.isEmpty else { return }
        guard let current = keyIndex else {
            keyIndex = 0
            return
        }
        keyIndex = min(max(current + delta, 0), rivals.count - 1)
    }
    #endif

    @ViewBuilder private var memberList: some View {
        if rivals.isEmpty {
            Text("No rivals to add yet.", bundle: .module)
                .font(.callout).foregroundStyle(.secondary)
        } else {
            ForEach(Array(rivals.enumerated()), id: \.element.id) { index, rival in
                let member = rival.groups.contains(group.id)
                Button {
                    friends.setMembership(!member, of: rival.publicKey, in: group.id)
                } label: {
                    HStack {
                        // Square (checkbox) not circle — membership is multi-select; a
                        // round check reads as a single-choice radio button.
                        Image(systemName: member ? "checkmark.square.fill" : "square")
                            .foregroundStyle(member ? Color.accentColor : .secondary)
                        Text(rival.displayName)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .modifier(memberRing(index))
            }
        }
    }

    @ViewBuilder private var chrome: some View {
        #if os(iOS)
        NavigationStack {
            ScrollView { content.padding(20) }
                .navigationTitle(Text("Edit squad", bundle: .module))
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
        VStack(spacing: 16) {
            Text("Edit squad", bundle: .module).font(.title2.bold())
            ScrollView { content }.frame(minHeight: 260)
            Button {
                dismiss()
            } label: {
                Text("Done", bundle: .module)
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .frame(minWidth: 340, minHeight: 380)
        // Arrows/Tab move through the member checkboxes, Return toggles the
        // focused one; yields while the name field is being typed in.
        .background(KeyCatcher(onKey: handleKey, yieldsToTextFields: true))
        #endif
    }
}
