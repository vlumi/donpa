import DonpaCore
import SwiftUI

/// A multi-select list of the group catalog with an inline "create new group" field,
/// for choosing which groups a friend belongs to. Reused by the friend-detail sheet
/// and the add-friend confirm sheet. Membership is a `Set<String>` of group ids the
/// caller binds; creating a group adds it to the catalog and selects it immediately.
struct GroupPicker: View {
    @ObservedObject var friends: FriendsStore
    /// Selected group ids. Two-way so both flows (persist-immediately vs. stage-then-
    /// apply) can drive it.
    @Binding var selection: Set<String>

    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if friends.groups.isEmpty {
                Text("No squads yet — create one below.", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(friends.groups) { group in
                    Button {
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
                }
            }

            HStack(spacing: 8) {
                TextField(text: $newName) {
                    Text("New squad", bundle: .module)
                }
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)
                Button(action: create) {
                    Text("Add", bundle: .module)
                }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
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
        guard let group = friends.createGroup(named: newName) else { return }
        selection.insert(group.id)
        newName = ""
    }
}
