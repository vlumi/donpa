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
    /// Tab-cyclable zones: the alias field, the squad checkboxes, the
    /// new-squad field, then the Remove button.
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
            // Their own name is fixed (it comes from their signed share); your alias
            // is the editable one.
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
                    fieldFocus: newGroupFocus
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
        case .down: if keys.zone == .groups { keys.move(1, count: friends.groups.count) }
        case .up: if keys.zone == .groups { keys.move(-1, count: friends.groups.count) }
        case .space:
            activateFocusedZone()
        case .enter:
            confirmOrActivate()
        case .escape:
            // The catcher owns keyDown, so Esc routes here — same
            // commit-then-close as Done.
            done()
        default: break
        }
    }

    /// Tab wraps through the zones, skipping the checkboxes when there are
    /// none; landing on a field starts editing.
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

    /// Desktop convention: Return presses the focused control when it's a
    /// button (or enters a field); on the checkboxes — or before any focus —
    /// it's the sheet's default — Done (commit-then-close).
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

    /// Done: commit a squad name typed but never committed with Create (silently
    /// discarding it was how squads "didn't appear"), then close.
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
            // Scrolls when the squad checklist + big text outgrow the sheet
            // (its sibling GroupEditView always had this); Done stays pinned
            // in the toolbar.
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
            // Scroll fallback for short windows / large text (ViewThatFits so
            // the sheet hugs its natural height when the checklist fits); the
            // title and Done stay pinned outside the scroller.
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
        // Tab: alias → checkboxes → new squad → Remove; Space toggles, Return
        // presses buttons/enters fields (else Done); yields while typing.
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
