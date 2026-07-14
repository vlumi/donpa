import DonpaCore
import SwiftUI

/// Rename, add/remove members, and delete for one group. There is no Save button —
/// every edit persists immediately via `FriendsStore`; Done just closes.
struct GroupEditView: View {
    let group: FriendGroup
    @ObservedObject var friends: FriendsStore
    @Environment(\.dismiss) private var dismiss
    private enum KeyZone: CaseIterable { case name, members, delete }
    @State private var keys = KeyCursor<KeyZone>()
    @FocusState private var nameFocused: Bool

    @State private var name: String
    @State private var confirmingDelete = false

    init(group: FriendGroup, friends: FriendsStore) {
        self.group = group
        self.friends = friends
        _name = State(initialValue: group.name)
    }

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
                nameField
                    .textFieldStyle(.roundedBorder)
                    .onChangeCompat(of: name) { friends.renameGroup(group.id, to: $0) }
            }

            Text("Members", bundle: .module).font(.caption).foregroundStyle(.secondary)
            memberList

            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Text("Delete squad", bundle: .module)
            }
            .keyFocusRing(keys.zone == .delete)
            .padding(.top, 4)
        }
    }

    private var nameField: some View {
        TextField(text: $name) { Text("Squad name", bundle: .module) }
            .focused($nameFocused)
            .keyFocusRing(keys.zone == .name)
    }

    #if os(macOS)
    private func handleKey(_ key: KeyCatcher.Key) {
        switch key {
        case .tab: cycleZone(1)
        case .backTab: cycleZone(-1)
        case .down, .up:
            if keys.zone == .members {
                keys.move(key == .down ? 1 : -1, count: rivals.count)
            }
        case .space:
            activateFocusedZone()
        case .enter:
            confirmOrActivate()
        case .escape:
            dismiss()
        default:
            if key == .click { keys.enter(nil) }  // mouse takes over
        }
    }

    /// Tab wraps through the zones, skipping the checkboxes when there are none.
    private func cycleZone(_ delta: Int) {
        var zones = KeyZone.allCases
        if rivals.isEmpty { zones.removeAll { $0 == .members } }
        if keys.cycle(delta, through: zones, entering: Self.entry) == .field {
            nameFocused = true
        }
    }

    private static func entry(_ zone: KeyZone) -> KeyCursor<KeyZone>.Entry {
        switch zone {
        case .name: return .field
        case .members: return .list(seed: 0)
        case .delete: return .plain
        }
    }

    /// Return presses the focused button (or enters the field); on the checkboxes,
    /// or before any focus, it's the sheet's default — Done.
    private func confirmOrActivate() {
        if keys.zone == .members || keys.zone == nil { dismiss() } else { activateFocusedZone() }
    }

    private func activateFocusedZone() {
        switch keys.zone {
        case nil:
            break
        case .name:
            nameFocused = true
        case .members:
            guard let index = keys.index, rivals.indices.contains(index) else { return }
            let rival = rivals[index]
            let member = rival.groups.contains(group.id)
            friends.setMembership(!member, of: rival.publicKey, in: group.id)
        case .delete:
            confirmingDelete = true
        }
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
                    keys.enter(.members)
                    keys.index = index
                    friends.setMembership(!member, of: rival.publicKey, in: group.id)
                } label: {
                    HStack {
                        Image(systemName: member ? "checkmark.square.fill" : "square")
                            .foregroundStyle(member ? Color.accentColor : .secondary)
                        Text(rival.displayName)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyFocusRing(keys.zone == .members && keys.index == index)
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
        // yieldsToTextFields: typing in the name field must never be hijacked.
        .background(KeyCatcher(onKey: handleKey, yieldsToTextFields: true))
        #endif
    }
}
