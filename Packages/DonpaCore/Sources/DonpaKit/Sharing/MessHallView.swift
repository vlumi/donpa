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
    /// `sheet(item:)` needs Identifiable; identity = the link itself.
    private struct NearbyPayload: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    /// The Nearby sheet's payload, built ONCE when the button is tapped —
    /// building it in the sheet's ViewBuilder published from within a view
    /// update (refreshFromCloud mutates the scoreboard) and looped forever.
    @State private var nearbyURL: NearbyPayload?
    private let identityStore = ShareIdentityStore()

    private enum Tab: Hashable { case rivals, squads }
    @State private var tab: Tab = .rivals
    #if os(macOS)
    /// The keyboard-focused row index in the CURRENT tab's list (arrow
    /// navigation); nil until the first arrow press, reset on tab switch.
    @State private var keyRowIndex: Int?
    #endif

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
            .escDismisses { dismiss() }
            .sheet(isPresented: $scanning) {
                AddRivalSheet { url in
                    scanning = false
                    dismiss()  // close the Mess hall so the prompt shows at root
                    onScanned?(url)
                }
            }
            .sheet(item: $nearbyURL) { payload in
                // Same payload the QR carries; same receive path a scan takes.
                NearbyExchangeView(
                    displayName: settings.shareName.isEmpty
                        ? String(localized: "A rival", bundle: .module)
                        : settings.shareName,
                    payloadURL: payload.url,
                    identityKey: identityStore.identity()?.publicKey
                ) { received in
                    nearbyURL = nil
                    dismiss()  // close the Mess hall so the prompt shows at root
                    onScanned?(received)
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

    /// The header, COMPACT by design (a taller one starves the rivals list —
    /// on a landscape SE it never appeared at all): the share card, then the
    /// tab picker sharing a row with the icon-only Add-rival door to the
    /// scanner. Nearby lives ON the card as its promoted default action.
    private var shareHeader: some View {
        VStack(spacing: 8) {
            ShareCardView(
                scoreboard: scoreboard, settings: settings,
                onNearby: { nearbyURL = currentShareURL().map(NearbyPayload.init) })
            HStack(spacing: 10) {
                tabPicker
                Button {
                    scanning = true
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(Text("Add rival", bundle: .module))
            }
        }
    }

    /// The signed share link, exactly as the share card builds it. Nil when there's
    /// no name yet (the card gates its own actions the same way) — a "?" card is a
    /// bad first handshake.
    private func currentShareURL() -> URL? {
        if scoreboard.isCloudActive { scoreboard.refreshFromCloud() }
        let trimmed = settings.shareName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            let identity = identityStore.identity(),
            let payload = SharePayloadBuilder.build(
                from: scoreboard, identity: identity, name: trimmed,
                includeCareer: settings.shareIncludeCareer, now: Date())
        else { return nil }
        return try? ShareLink.url(for: payload)
    }

    /// Sync lives here too, not only in the Service Record: the Mess hall is where
    /// sync questions arise (the share card's footer already talks about it), and the
    /// same self-contained control reads shared state, so mounting it twice is free.
    private var syncFooter: some View {
        VStack(spacing: 0) {
            Divider()
            SyncFooterControl(settings: settings, scoreboard: scoreboard)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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
                ForEach(Array(rivals.enumerated()), id: \.element.id) { index, rival in
                    // Tap = compare (the primary action); trailing pencil = edit.
                    rowButton(compare: { comparingRival = rival }, edit: { editingRival = rival }) {
                        FriendRow(friend: rival, groupNames: groupNames(for: rival))
                    }
                    .modifier(keyFocusRing(index))
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
                ForEach(Array(friends.groups.enumerated()), id: \.element.id) { index, group in
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
                    .modifier(keyFocusRing(index))
                }
            }
        }
    }

}

// MARK: Keyboard driving (same file: the helpers read private state)

extension MessHallView {
    /// The keyboard-focus ring for a list row (macOS arrow navigation);
    /// a no-op ring elsewhere.
    private func keyFocusRing(_ index: Int) -> FocusRing {
        #if os(macOS)
        return FocusRing(focused: keyRowIndex == index, inset: 2)
        #else
        return FocusRing(focused: false, inset: 0)
        #endif
    }

    #if os(macOS)
    /// Arrow/Return/E/⌘-number keyboard driving — the Record's vocabulary on
    /// the social lists. ⌘1/⌘2 arrive here because the KeyCatcher consumes
    /// number equivalents; they mirror the hidden tab buttons.
    private func handleKey(_ key: KeyCatcher.Key) {
        switch key {
        case .down, .tab: moveRowFocus(1)
        case .up, .backTab: moveRowFocus(-1)
        case .enter: activateFocusedRow(edit: false)
        case .character("e"): activateFocusedRow(edit: true)
        case .character("a"): scanning = true
        case .character("n"):
            // Same gate as the card's button: no name → no card to swap.
            nearbyURL = currentShareURL().map(NearbyPayload.init)
        case .escape: dismiss()
        case .family(1):
            tab = .rivals
            keyRowIndex = nil
        case .family(2):
            tab = .squads
            keyRowIndex = nil
        case .left, .right, .family, .character:
            break
        }
    }

    private var focusedRowCount: Int {
        tab == .rivals ? rivals.count : friends.groups.count
    }

    private func moveRowFocus(_ delta: Int) {
        guard focusedRowCount > 0 else { return }
        guard let current = keyRowIndex else {
            keyRowIndex = 0
            return
        }
        keyRowIndex = min(max(current + delta, 0), focusedRowCount - 1)
    }

    /// Return = the row's tap (compare); E = its pencil (edit).
    private func activateFocusedRow(edit: Bool) {
        guard let index = keyRowIndex else { return }
        switch tab {
        case .rivals:
            guard rivals.indices.contains(index) else { return }
            if edit { editingRival = rivals[index] } else { comparingRival = rivals[index] }
        case .squads:
            guard friends.groups.indices.contains(index) else { return }
            let group = friends.groups[index]
            if edit {
                editingGroup = group
            } else if !friends.members(of: group.id).isEmpty {
                comparingGroup = group
            }
        }
    }
    #endif

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
                tabContent
            }
            .safeAreaInset(edge: .bottom) { syncFooter.background(.bar) }
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
            // The list is the flexible part: an explicit ideal, because a List's
            // ideal height resolves near ZERO under a sheet's unbounded proposal —
            // the sheet then presents at the frame minimums and the fixed chrome
            // clips top and bottom.
            tabContent.frame(minHeight: 180, idealHeight: 300)
            HStack(spacing: 12) {
                SyncFooterControl(settings: settings, scoreboard: scoreboard)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Done", bundle: .module)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        // No outer minHeight: the sheet's floor derives from the content's own
        // minimums, so nothing it can present or resize to clips the chrome
        // (a fixed floor below the content minimum clipped both ends). The
        // ideal keeps it inside the minimum game window.
        .frame(minWidth: 600, idealHeight: 600)
        // Arrows move the row focus, Return compares, E edits, ⌘1/⌘2 switch
        // tabs, Esc closes. Yields while a name field is being edited, so
        // typing is never hijacked (Return there still submits the field).
        .background(KeyCatcher(onKey: handleKey, yieldsToTextFields: true))
        #endif
    }
}
