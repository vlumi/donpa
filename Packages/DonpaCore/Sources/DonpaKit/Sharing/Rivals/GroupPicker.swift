import DonpaCore
import SwiftUI

/// Multi-select group checklist with an inline "create new squad" field.
struct GroupPicker: View {
    @ObservedObject var friends: FriendsStore
    /// Selected group ids.
    @Binding var selection: Set<String>
    /// The new-squad field's un-committed text, owned by the HOST so its confirm/Done
    /// can commit a typed-but-never-created squad instead of silently discarding it.
    @Binding var pendingName: String
    /// The HOST's keyboard-focused checkbox index — the host owns key handling so Tab
    /// can leave this list (a self-contained catcher trapped Tab and swallowed Esc).
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
                // "Create", not "Add" — the host sheet's confirm button already says Add.
                Button(action: create) {
                    Text("Create", bundle: .module)
                }
                .disabled(pendingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .keyFocusRing(fieldKeyFocused)
            .onPulse(fieldFocus) { fieldFocused = true }
        }
    }

    /// The hosts' keyboard path: Space on a focused checkbox.
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

    private func create() {
        guard let group = friends.createGroup(named: pendingName) else { return }
        selection.insert(group.id)
        pendingName = ""
    }
}
