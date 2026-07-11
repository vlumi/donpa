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
    #if os(macOS)
    /// Tab-cyclable zones: the squad checkboxes, then the Remove button.
    private enum KeyZone: CaseIterable { case groups, remove }
    @State private var keyZone: KeyZone = .groups
    /// The focused checkbox while the groups zone is active.
    @State private var keyIndex: Int?
    #endif
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
                TextField(text: $alias) {
                    Text("Optional", bundle: .module)
                }
                .textFieldStyle(.roundedBorder)
                .onChangeCompat(of: alias) { friends.setAlias($0, for: friend.publicKey) }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Squads", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
                GroupPicker(
                    friends: friends, selection: $groupSelection,
                    pendingName: $pendingGroupName,
                    keyFocusIndex: pickerFocusIndex
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
            .modifier(removeRing)
            .padding(.top, 4)
        }
    }

    private var pickerFocusIndex: Int? {
        #if os(macOS)
        return keyZone == .groups ? keyIndex : nil
        #else
        return nil
        #endif
    }

    private var removeRing: FocusRing {
        #if os(macOS)
        return FocusRing(focused: keyZone == .remove, inset: 2)
        #else
        return FocusRing(focused: false, inset: 0)
        #endif
    }

    #if os(macOS)
    private func handleKey(_ key: KeyCatcher.Key) {
        switch key {
        case .tab, .backTab:
            // Two zones: Tab toggles between them (wrapping either way).
            keyZone = keyZone == .groups ? .remove : .groups
        case .down: if keyZone == .groups { moveFocus(1) }
        case .up: if keyZone == .groups { moveFocus(-1) }
        case .enter:
            activateFocusedZone()
        case .escape:
            // The catcher owns keyDown, so the sheet's cancel never sees Esc —
            // route it to the same commit-then-close Done runs.
            done()
        default: break
        }
    }

    private func activateFocusedZone() {
        switch keyZone {
        case .groups:
            if let index = keyIndex { toggleGroup(at: index) }
        case .remove:
            confirmingRemove = true
        }
    }

    private func moveFocus(_ delta: Int) {
        guard !friends.groups.isEmpty else { return }
        guard let current = keyIndex else {
            keyIndex = 0
            return
        }
        keyIndex = min(max(current + delta, 0), friends.groups.count - 1)
    }

    private func toggleGroup(at index: Int) {
        guard friends.groups.indices.contains(index) else { return }
        let id = friends.groups[index].id
        if groupSelection.contains(id) {
            groupSelection.remove(id)
        } else {
            groupSelection.insert(id)
        }
        friends.setGroups(Array(groupSelection), for: friend.publicKey)
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
        // Tab: checkboxes ↔ Remove; arrows walk the checkboxes, Return
        // toggles; yields while the alias/new-squad field is being typed in.
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
