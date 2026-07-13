import DonpaCore
import SwiftUI

/// A multi-select list of the group catalog with an inline "create new squad" field,
/// for choosing which groups a friend belongs to. Reused by the friend-detail sheet
/// and the add-friend confirm sheet. Membership is a `Set<String>` of group ids the
/// caller binds; creating a group adds it to the catalog and selects it immediately.
struct GroupPicker: View {
    @ObservedObject var friends: FriendsStore
    /// Selected group ids. Two-way so both flows (persist-immediately vs. stage-then-
    /// apply) can drive it.
    @Binding var selection: Set<String>
    /// The new-squad field's un-committed text, owned by the HOST so its confirm/Done
    /// can commit a typed-but-not-created squad instead of silently discarding it
    /// (the field trap: type a name, tap the sheet's big button, squad never existed).
    @Binding var pendingName: String
    /// The HOST's keyboard-focused checkbox index (the host owns the key
    /// handling so Tab can move focus OUT of this list to its other controls;
    /// a self-contained catcher trapped Tab and swallowed the sheet's Esc).
    var keyFocusIndex: Int?
    /// Ring for the new-squad row while the host's Tab focuses it.
    var fieldKeyFocused: Bool = false
    /// Fired by the host to put the caret in the new-squad field.
    var fieldFocus = Pulse()
    /// A tapped checkbox reports its row, so the host moves key focus there.
    var onRowTap: ((Int) -> Void)?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if friends.groups.isEmpty {
                Text("No squads yet — create one below.", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(friends.groups.enumerated()), id: \.element.id) { index, group in
                    Button {
                        onRowTap?(index)
                        toggle(group.id)
                    } label: {
                        HStack {
                            // Square (checkbox) not circle — multi-select, not radio.
                            Image(
                                systemName: selection.contains(group.id)
                                    ? "checkmark.square.fill" : "square"
                            )
                            .foregroundStyle(
                                selection.contains(group.id) ? Color.accentColor : .secondary)
                            Text(group.name)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyFocusRing(keyFocusIndex == index)
                }
            }

            HStack(spacing: 8) {
                TextField(text: $pendingName) {
                    Text("New squad", bundle: .module)
                }
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit(create)
                // "Create", NOT "Add" — the sheet's own confirm button also says
                // Add, and two same-named buttons doing different things is a trap.
                Button(action: create) {
                    Text("Create", bundle: .module)
                }
                .disabled(pendingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .keyFocusRing(fieldKeyFocused)
            .onPulse(fieldFocus) { fieldFocused = true }
        }
    }

    /// Toggle by index in a selection the host owns — its keyboard path
    /// (Space on a focused checkbox), shared by both host sheets.
    static func toggle(at index: Int, of groups: [FriendGroup], in selection: inout Set<String>) {
        guard groups.indices.contains(index) else { return }
        let id = groups[index].id
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    private func toggle(_ id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    /// Create (or reuse) a group by the typed name and select it.
    private func create() {
        guard let group = friends.createGroup(named: pendingName) else { return }
        selection.insert(group.id)
        pendingName = ""
    }
}
