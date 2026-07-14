import DonpaCore
import SwiftUI

/// A friend's detail: your local alias (which survives their own renames), squad
/// membership, and removal. There is no Save button — every edit persists
/// immediately via `FriendsStore`; Done just closes.
struct FriendDetailView: View {
    let friend: Friend
    @ObservedObject var friends: FriendsStore
    @Environment(\.dismiss) private var dismiss

    @State private var alias: String
    @State private var groupSelection: Set<String>
    @State private var confirmingRemove = false
    private enum KeyZone: CaseIterable { case alias, groups, newGroup, remove }
    @State private var keys = KeyCursor<KeyZone>()
    @FocusState private var aliasFocused: Bool
    @State private var newGroupFocus = Pulse()
    /// A typed-but-not-created new squad name; Done commits it (see GroupPicker).
    @State private var pendingGroupName = ""

    init(friend: Friend, friends: FriendsStore) {
        self.friend = friend
        self.friends = friends
        _alias = State(initialValue: friend.localAlias ?? "")
        _groupSelection = State(initialValue: Set(friend.groups))
    }

    var body: some View {
        chrome
            .escDismisses { done() }
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Their shared name is fixed (it comes from their signed share); only
            // your alias is editable.
            VStack(alignment: .leading, spacing: 4) {
                Text("Shared name", bundle: .module).font(.caption).foregroundStyle(.secondary)
                Text(friend.sharedName).font(.body)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Your name for them", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
                aliasField
                    .textFieldStyle(.roundedBorder)
                    .onChangeCompat(of: alias) { friends.setAlias($0, for: friend.publicKey) }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Squads", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
                GroupPicker(
                    friends: friends, selection: $groupSelection,
                    pendingName: $pendingGroupName,
                    keyFocusIndex: keys.zone == .groups ? keys.index : nil,
                    fieldKeyFocused: keys.zone == .newGroup,
                    fieldFocus: newGroupFocus,
                    onRowTap: { index in
                        keys.enter(.groups)
                        keys.index = index
                    }
                )
                .onChangeCompat(of: groupSelection) {
                    friends.setGroups(Array($0), for: friend.publicKey)
                }
            }

            Button(role: .destructive) {
                confirmingRemove = true
            } label: {
                Text("Remove rival", bundle: .module)
            }
            .keyFocusRing(keys.zone == .remove)
            .padding(.top, 4)
        }
    }

    private var aliasField: some View {
        TextField(text: $alias) {
            Text("Optional", bundle: .module)
        }
        .focused($aliasFocused)
        .keyFocusRing(keys.zone == .alias)
    }

    #if os(macOS)
    private func handleKey(_ key: KeyCatcher.Key) {
        switch key {
        case .tab: cycleZone(1)
        case .backTab: cycleZone(-1)
        case .down, .up:
            if keys.zone == .groups {
                keys.move(key == .down ? 1 : -1, count: friends.groups.count)
            }
        case .space:
            activateFocusedZone()
        case .enter:
            confirmOrActivate()
        case .escape:
            done()  // same commit-then-close as Done
        default:
            if key == .click { keys.enter(nil) }  // mouse takes over
        }
    }

    /// Tab wraps through the zones, skipping the checkboxes when there are none.
    private func cycleZone(_ delta: Int) {
        var zones = KeyZone.allCases
        if friends.groups.isEmpty { zones.removeAll { $0 == .groups } }
        switch keys.cycle(delta, through: zones, entering: Self.entry) {
        case .field where keys.zone == .alias: aliasFocused = true
        case .field: newGroupFocus.fire()
        default: break
        }
    }

    private static func entry(_ zone: KeyZone) -> KeyCursor<KeyZone>.Entry {
        switch zone {
        case .alias, .newGroup: return .field
        case .groups: return .list(seed: 0)
        case .remove: return .plain
        }
    }

    /// Return presses the focused button (or enters a field); on the checkboxes,
    /// or before any focus, it's the sheet's default — Done.
    private func confirmOrActivate() {
        if keys.zone == .groups || keys.zone == nil { done() } else { activateFocusedZone() }
    }

    private func activateFocusedZone() {
        switch keys.zone {
        case .alias:
            aliasFocused = true
        case .groups:
            guard let index = keys.index else { return }
            GroupPicker.toggle(at: index, of: friends.groups, in: &groupSelection)
        case .newGroup:
            newGroupFocus.fire()
        case .remove:
            confirmingRemove = true
        case nil:
            break
        }
    }
    #endif

    private func remove() {
        friends.delete(friend.publicKey)
        dismiss()
    }

    /// Commit a squad name typed but never created (silently discarding it would
    /// lose the squad), then close.
    private func done() {
        if let pending = friends.createGroup(named: pendingGroupName) {
            groupSelection.insert(pending.id)
            friends.setGroups(Array(groupSelection), for: friend.publicKey)
        }
        dismiss()
    }

    @ViewBuilder private var chrome: some View {
        #if os(iOS)
        NavigationStack {
            ScrollView {
                content.padding(20)
            }
            .navigationTitle(Text(friend.displayName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: done) {
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
            ViewThatFits(in: .vertical) {
                content
                ScrollView { content }
            }
            Button(action: done) {
                Text("Done", bundle: .module)
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(minWidth: 340)
        // yieldsToTextFields: typing in the fields must never be hijacked.
        .background(KeyCatcher(onKey: handleKey, yieldsToTextFields: true))
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
