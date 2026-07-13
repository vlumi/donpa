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
    /// Tab-cyclable zones: the name field, the member checkboxes, then the
    /// Delete button.
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
            // The catcher owns keyDown, so Esc routes here too.
            dismiss()
        default:
            // Mouse click: the pointer takes over; the ring stands down.
            if key == .click { keys.enter(nil) }
        }
    }

    /// Tab wraps through the zones, skipping the checkboxes when there are
    /// none; landing on the field starts editing.
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

    /// Desktop convention: Return presses the focused control when it's a
    /// button (or enters the field); on the checkboxes — or before any
    /// focus — it's the sheet's default — Done.
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
                    // Click takes the keyboard focus with it.
                    keys.enter(.members)
                    keys.index = index
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
        // Tab: name → checkboxes → Delete; Space toggles, Return presses
        // buttons/enters the field (else Done); yields while typing.
        .background(KeyCatcher(onKey: handleKey, yieldsToTextFields: true))
        #endif
    }
}
