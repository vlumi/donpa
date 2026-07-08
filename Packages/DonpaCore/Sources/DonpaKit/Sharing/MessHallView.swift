import DonpaCore
import SwiftUI

/// The **Mess hall** — where units mingle: your share card, your rivals, and your
/// squads, one social screen (FI *Sotku*, JA 食堂). Two segmented tabs, **Rivals**
/// and **Squads**, over one `FriendsStore`, under a share/scan header. In both tabs,
/// tapping a row COMPARES you head-to-head; a trailing pencil edits (a rival's
/// alias/squads/removal, or a squad's name/members/deletion). Sorted alphabetically.
/// Read-only over the store except through its methods — the display-merge invariant
/// means removing an entry just drops its data.
struct MessHallView: View {
    @ObservedObject var friends: FriendsStore
    @ObservedObject var scoreboard: Scoreboard
    @ObservedObject var settings: Settings
    /// Route a scanned rival URL into the receive flow: the host closes this sheet
    /// and hands the URL to the root classify/prompt path (same as a tapped link).
    var onScanned: ((URL) -> Void)?
    /// Start a game on a board picked inside a head-to-head (the rematch loop).
    /// This view closes itself; the host routes the config into a fresh game.
    var onPlay: ((GameConfig) -> Void)?
    @Environment(\.dismiss) private var dismiss

    /// Whether the Add-rival scanner sheet is presented.
    @State private var scanning = false

    private enum Tab: Hashable { case rivals, squads }
    @State private var tab: Tab = .rivals

    /// The rival whose detail (edit) sheet is open, or nil.
    @State private var editingRival: Friend?
    /// The rival being compared head-to-head, or nil.
    @State private var comparingRival: Friend?
    /// The group being edited (name / members / delete), or nil.
    @State private var editingGroup: FriendGroup?
    /// The group being compared head-to-head, or nil.
    @State private var comparingGroup: FriendGroup?
    /// A new group's name field (Groups tab).
    @State private var newGroupName = ""

    /// Rivals alphabetical; ties broken by key for a stable order.
    private var rivals: [Friend] {
        friends.friends.sorted {
            let byName = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            if byName != .orderedSame { return byName == .orderedAscending }
            return $0.publicKey.lexicographicallyPrecedes($1.publicKey)
        }
    }

    var body: some View {
        chrome
            .sheet(isPresented: $scanning) {
                AddRivalSheet { url in
                    scanning = false
                    dismiss()  // close the Mess hall so the prompt shows at root
                    onScanned?(url)
                }
            }
            .sheet(item: $editingRival) { FriendDetailView(friend: $0, friends: friends) }
            .sheet(item: $comparingRival) { rival in
                HeadToHeadView(
                    scoreboard: scoreboard, opponentName: rival.displayName,
                    result: RivalRanking.headToHead(with: rival, scoreboard: scoreboard),
                    // Career comparison only when this rival opted to share it.
                    career: rival.career.map {
                        (yours: SharePayloadBuilder.career(from: scoreboard), theirs: $0)
                    },
                    onPlay: play)
            }
            .sheet(item: $editingGroup) { GroupEditView(group: $0, friends: friends) }
            .sheet(item: $comparingGroup) { group in
                HeadToHeadView(
                    scoreboard: scoreboard, opponentName: group.name,
                    result: RivalRanking.headToHead(
                        withGroup: friends.members(of: group.id), scoreboard: scoreboard),
                    onPlay: play)
            }
    }

    /// A head-to-head row's play tapped: collapse this whole surface (the sheet
    /// stack folds with it) and hand the board to the host to start the game.
    private func play(_ config: GameConfig) {
        comparingRival = nil
        comparingGroup = nil
        dismiss()
        onPlay?(config)
    }

    // MARK: Share / scan header

    /// Your share card, INLINE (the wireframe's shape — sharing is the social act,
    /// one glance away, no sheet), and the Add-rival door to the scanner.
    private var shareHeader: some View {
        VStack(spacing: 10) {
            Text("Share my scores", bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ShareCardView(scoreboard: scoreboard, settings: settings)
            Button {
                scanning = true
            } label: {
                Label {
                    Text("Add rival", bundle: .module)
                } icon: {
                    Image(systemName: "qrcode.viewfinder")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: Tabs

    private var tabPicker: some View {
        Picker(selection: $tab) {
            Text("Rivals", bundle: .module).tag(Tab.rivals)
            Text("Squads", bundle: .module).tag(Tab.squads)
        } label: {
            Text("View", bundle: .module)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        #if os(macOS)
        // ⌘1 / ⌘2 switch tabs (standard macOS segment nav). Hidden zero-size buttons
        // carry the shortcuts without adding visible chrome.
        .background {
            Group {
                Button("") { tab = .rivals }.keyboardShortcut("1", modifiers: .command)
                Button("") { tab = .squads }.keyboardShortcut("2", modifiers: .command)
            }
            .opacity(0)
        }
        #endif
    }

    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .rivals: rivalsList
        case .squads: groupsList
        }
    }

    // MARK: Rivals tab

    @ViewBuilder private var rivalsList: some View {
        if rivals.isEmpty {
            emptyState(
                icon: "person.2", title: "No rivals yet.",
                detail: "Add a rival's scores by scanning their QR code or opening a share link.")
        } else {
            List {
                ForEach(rivals) { rival in
                    // Tap = compare (the primary action); trailing pencil = edit.
                    rowButton(compare: { comparingRival = rival }, edit: { editingRival = rival }) {
                        FriendRow(friend: rival, groupNames: groupNames(for: rival))
                    }
                }
                .onDelete { offsets in
                    offsets.map { rivals[$0].publicKey }.forEach { friends.delete($0) }
                }
            }
        }
    }

    /// A rival's group names, resolved from their membership ids via the catalog.
    private func groupNames(for friend: Friend) -> [String] {
        friend.groups.compactMap { id in friends.groups.first { $0.id == id }?.name }
    }

    // MARK: Groups tab

    @ViewBuilder private var groupsList: some View {
        List {
            // Create a group, then jump straight into editing it (name + add members).
            HStack(spacing: 8) {
                TextField(text: $newGroupName) { Text("New squad", bundle: .module) }
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(createGroup)
                Button(action: createGroup) { Text("Add", bundle: .module) }
                    .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if friends.groups.isEmpty {
                Text("No squads yet — create one above.", bundle: .module)
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(friends.groups) { group in
                    // Tap = compare vs the group's best; pencil = edit (name/members/delete).
                    rowButton(
                        compare: { comparingGroup = group },
                        edit: { editingGroup = group },
                        compareDisabled: friends.members(of: group.id).isEmpty
                    ) {
                        HStack {
                            Text(group.name)
                            Spacer()
                            Text("\(friends.members(of: group.id).count)", bundle: .module)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func createGroup() {
        guard let group = friends.createGroup(named: newGroupName) else { return }
        newGroupName = ""
        editingGroup = group  // open the edit view so you can add rivals right away
    }

    // MARK: Shared row

    /// A list row whose body taps to compare, with a trailing pencil to edit. Compare
    /// can be disabled (e.g. an empty group has nothing to compare).
    @ViewBuilder private func rowButton<Content: View>(
        compare: @escaping () -> Void, edit: @escaping () -> Void,
        compareDisabled: Bool = false, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Button(action: compare) { content().contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .disabled(compareDisabled)
            Button(action: edit) {
                Image(systemName: "pencil").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Edit", bundle: .module))
        }
    }

    private func emptyState(
        icon: String, title: LocalizedStringKey, detail: LocalizedStringKey
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 48)).foregroundStyle(.secondary)
            Text(title, bundle: .module).font(.headline)
            Text(detail, bundle: .module)
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Chrome

    @ViewBuilder private var chrome: some View {
        #if os(iOS)
        NavigationStack {
            VStack(spacing: 0) {
                shareHeader.padding([.horizontal, .top], 12)
                tabPicker.padding([.horizontal, .top], 12)
                tabContent
            }
            .navigationTitle(Text("Mess hall", bundle: .module))
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
        VStack(spacing: 12) {
            Text("Mess hall", bundle: .module).font(.title2.bold())
            shareHeader
            tabPicker
            tabContent.frame(minHeight: 260)
            Button {
                dismiss()
            } label: {
                Text("Done", bundle: .module)
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        // Wide enough that the share card crosses its directly-scannable QR
        // threshold (240pt needs a ~520pt card; 360 left it at the tap-to-zoom thumb).
        .frame(minWidth: 600, minHeight: 420)
        #endif
    }
}

/// A rival's list row: display name (your alias wins), their share date, groups, and a
/// compact score summary (wins · boards), right-aligned.
private struct FriendRow: View {
    let friend: Friend
    let groupNames: [String]

    private var boardsWon: Int { friend.scores.filter { $0.wins > 0 }.count }
    private var totalWins: Int { friend.scores.reduce(0) { $0 + $1.wins } }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName).font(.body.bold())
                    .lineLimit(1).minimumScaleFactor(0.7)
                if friend.localAlias != nil {
                    Text(friend.sharedName).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                // Their share's own timestamp — makes plain these are a SNAPSHOT that
                // only changes when they re-share, not something that updates itself.
                Text(
                    "Updated \(friend.lastIssuedAt.formatted(date: .abbreviated, time: .omitted))",
                    bundle: .module
                )
                .font(.caption2).foregroundStyle(.secondary)
                if !groupNames.isEmpty {
                    // .secondary, not .tertiary: squad membership is real info,
                    // and tertiary caption2 sat near-invisible for low vision.
                    Text(groupNames.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(totalWins) wins", bundle: .module).font(.subheadline.bold())
                Text("\(boardsWon) boards", bundle: .module)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        // One row, one utterance — six separate texts read as disjointed
        // fragments under VoiceOver.
        .accessibilityElement(children: .combine)
    }
}
