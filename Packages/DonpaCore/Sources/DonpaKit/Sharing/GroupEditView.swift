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
    /// Tab-cyclable zones: the name field, the member checkboxes, then the
    /// Delete button.
    private enum KeyZone: CaseIterable { case name, members, delete }
    @State private var keyZone: KeyZone = .name
    /// The keyboard-focused member checkbox (arrow navigation).
    @State private var keyIndex: Int?
    @FocusState private var nameFocused: Bool
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
                nameField
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
            .modifier(deleteRing)
            .padding(.top, 4)
        }
    }

    private func memberRing(_ index: Int) -> FocusRing {
        #if os(macOS)
        return FocusRing(focused: keyZone == .members && keyIndex == index, inset: 2)
        #else
        return FocusRing(focused: false, inset: 0)
        #endif
    }

    private var deleteRing: FocusRing {
        #if os(macOS)
        return FocusRing(focused: keyZone == .delete, inset: 2)
        #else
        return FocusRing(focused: false, inset: 0)
        #endif
    }

    /// The squad-name field, focusable from the keyboard on macOS.
    @ViewBuilder private var nameField: some View {
        let field = TextField(text: $name) { Text("Squad name", bundle: .module) }
        #if os(macOS)
        field
            .focused($nameFocused)
            .modifier(FocusRing(focused: keyZone == .name, inset: 2))
        #else
        field
        #endif
    }

    #if os(macOS)
    private func handleKey(_ key: KeyCatcher.Key) {
        switch key {
        case .tab: moveZone(1)
        case .backTab: moveZone(-1)
        case .down: if keyZone == .members { moveFocus(1) }
        case .up: if keyZone == .members { moveFocus(-1) }
        case .space:
            activateFocusedZone()
        case .enter:
            confirmOrActivate()
        case .escape:
            // The catcher owns keyDown, so Esc routes here too.
            dismiss()
        default: break
        }
    }

    /// Desktop convention: Return presses the focused control when it's a
    /// button (or enters the field); on the checkboxes it's the sheet's
    /// default — Done.
    private func confirmOrActivate() {
        if keyZone == .members { dismiss() } else { activateFocusedZone() }
    }

    /// Tab wraps through the zones, skipping the checkboxes when there are none.
    private func moveZone(_ delta: Int) {
        var zones = KeyZone.allCases
        if rivals.isEmpty { zones.removeAll { $0 == .members } }
        let i = zones.firstIndex(of: keyZone) ?? 0
        keyZone = zones[(i + delta + zones.count) % zones.count]
    }

    private func activateFocusedZone() {
        switch keyZone {
        case .name:
            nameFocused = true
        case .members:
            guard let index = keyIndex, rivals.indices.contains(index) else { return }
            let rival = rivals[index]
            let member = rival.groups.contains(group.id)
            friends.setMembership(!member, of: rival.publicKey, in: group.id)
        case .delete:
            confirmingDelete = true
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
        // Tab: name → checkboxes → Delete; Space toggles, Return presses
        // buttons/enters the field (else Done); yields while typing.
        .background(KeyCatcher(onKey: handleKey, yieldsToTextFields: true))
        #endif
    }
}
