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
    #if os(macOS)
    /// The keyboard-focused checkbox row (arrow navigation); nil until the
    /// first press.
    @State private var keyIndex: Int?
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if friends.groups.isEmpty {
                Text("No squads yet — create one below.", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(friends.groups.enumerated()), id: \.element.id) { index, group in
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
                    .modifier(checkboxRing(index))
                }
            }

            HStack(spacing: 8) {
                TextField(text: $pendingName) {
                    Text("New squad", bundle: .module)
                }
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)
                // "Create", NOT "Add" — the sheet's own confirm button also says
                // Add, and two same-named buttons doing different things is a trap.
                Button(action: create) {
                    Text("Create", bundle: .module)
                }
                .disabled(pendingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        #if os(macOS)
        // Arrows/Tab move through the checkboxes, Return toggles the focused
        // one; yields while the new-squad field is being typed in (its Return
        // still creates). Esc reaches the sheet's cancel as a key equivalent
        // before this catcher ever sees it.
        .background(KeyCatcher(onKey: handleKey, yieldsToTextFields: true))
        #endif
    }

    private func checkboxRing(_ index: Int) -> FocusRing {
        #if os(macOS)
        return FocusRing(focused: keyIndex == index, inset: 2)
        #else
        return FocusRing(focused: false, inset: 0)
        #endif
    }

    #if os(macOS)
    private func handleKey(_ key: KeyCatcher.Key) {
        switch key {
        case .down, .tab: moveFocus(1)
        case .up, .backTab: moveFocus(-1)
        case .enter:
            guard let index = keyIndex, friends.groups.indices.contains(index) else { return }
            toggle(friends.groups[index].id)
        default: break
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
    #endif

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
