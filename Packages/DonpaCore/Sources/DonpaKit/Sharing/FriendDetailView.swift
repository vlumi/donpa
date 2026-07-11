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
    /// Tab-cyclable zones: the alias field, the squad checkboxes, the
    /// new-squad field, then the Remove button. Nil until the keyboard
    /// enters the sheet.
    private enum KeyZone: CaseIterable { case alias, groups, newGroup, remove }
    @State private var keyZone: KeyZone?
    /// The focused checkbox while the groups zone is active.
    @State private var keyIndex: Int?
    @FocusState private var aliasFocused: Bool
    @State private var newGroupFocusTick = 0
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
                    keyFocusIndex: pickerFocusIndex,
                    fieldKeyFocused: newGroupRingFocused,
                    fieldFocusTick: newGroupTick
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

    /// The alias field, focusable from the keyboard on macOS.
    @ViewBuilder private var aliasField: some View {
        let field = TextField(text: $alias) {
            Text("Optional", bundle: .module)
        }
        #if os(macOS)
        field
            .focused($aliasFocused)
            .modifier(FocusRing(focused: keyZone == .alias, inset: 2))
        #else
        field
        #endif
    }

    private var pickerFocusIndex: Int? {
        #if os(macOS)
        return keyZone == .groups ? keyIndex : nil
        #else
        return nil
        #endif
    }

    private var newGroupRingFocused: Bool {
        #if os(macOS)
        return keyZone == .newGroup
        #else
        return false
        #endif
    }

    private var newGroupTick: Int {
        #if os(macOS)
        return newGroupFocusTick
        #else
        return 0
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
        case .tab: moveZone(1)
        case .backTab: moveZone(-1)
        case .down: if keyZone == .groups { moveFocus(1) }
        case .up: if keyZone == .groups { moveFocus(-1) }
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

    /// Desktop convention: Return presses the focused control when it's a
    /// button (or enters a field); on the checkboxes — or before any focus —
    /// it's the sheet's default — Done (commit-then-close).
    private func confirmOrActivate() {
        if keyZone == .groups || keyZone == nil { done() } else { activateFocusedZone() }
    }

    /// Tab wraps through the zones, skipping the checkboxes when there are none.
    private func moveZone(_ delta: Int) {
        var zones = KeyZone.allCases
        if friends.groups.isEmpty { zones.removeAll { $0 == .groups } }
        guard let current = keyZone, let i = zones.firstIndex(of: current) else {
            // Nothing focused yet: the first Tab enters the ring at its start
            // (Shift-Tab at its end).
            enter(delta > 0 ? zones.first : zones.last)
            return
        }
        enter(zones[(i + delta + zones.count) % zones.count])
    }

    /// Landing on a field starts editing (a focused field IS an editing
    /// field); landing on the checkboxes seeds the item focus so the arrows
    /// show where they'll work from.
    private func enter(_ zone: KeyZone?) {
        keyZone = zone
        switch zone {
        case .alias: aliasFocused = true
        case .newGroup: newGroupFocusTick += 1
        case .groups: if keyIndex == nil { keyIndex = 0 }
        default: break
        }
    }

    private func activateFocusedZone() {
        switch keyZone {
        case .alias:
            aliasFocused = true
        case .groups:
            if let index = keyIndex { toggleGroup(at: index) }
        case .newGroup:
            newGroupFocusTick += 1
        case .remove:
            confirmingRemove = true
        case nil:
            break
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
