import DonpaCore
import SwiftUI

/// A friend's detail: your local alias (which survives their own renames) and
/// removal. There is no Save button — every edit persists immediately via
/// `FriendsStore`; Done just closes. (Squad membership is parked with the
/// squads UI — see DECISIONS.md.)
struct FriendDetailView: View {
    let friend: Friend
    @ObservedObject var friends: FriendsStore
    @Environment(\.dismiss) private var dismiss

    @State private var alias: String
    @State private var confirmingRemove = false
    private enum KeyZone: CaseIterable { case alias, remove }
    @State private var keys = KeyCursor<KeyZone>()
    @FocusState private var aliasFocused: Bool

    init(friend: Friend, friends: FriendsStore) {
        self.friend = friend
        self.friends = friends
        _alias = State(initialValue: friend.localAlias ?? "")
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

    private func cycleZone(_ delta: Int) {
        switch keys.cycle(delta, through: KeyZone.allCases, entering: Self.entry) {
        case .field: aliasFocused = true
        default: break
        }
    }

    private static func entry(_ zone: KeyZone) -> KeyCursor<KeyZone>.Entry {
        switch zone {
        case .alias: return .field
        case .remove: return .plain
        }
    }

    /// Return presses the focused button (or enters a field); before any
    /// focus it's the sheet's default — Done.
    private func confirmOrActivate() {
        if keys.zone == nil { done() } else { activateFocusedZone() }
    }

    private func activateFocusedZone() {
        switch keys.zone {
        case .alias:
            aliasFocused = true
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

    private func done() {
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
