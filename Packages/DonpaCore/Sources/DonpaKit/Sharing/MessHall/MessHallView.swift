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
    @ObservedObject var dailyStore: DailyStore
    /// Route a scanned rival URL into the receive flow: the host closes this sheet
    /// and hands the URL to the root classify/prompt path (same as a tapped link).
    var onScanned: ((URL) -> Void)?
    /// Start a game on a board picked inside a head-to-head (the rematch loop).
    /// This view closes itself; the host routes the config into a fresh game.
    var onPlay: ((GameConfig) -> Void)?
    @Environment(\.dismiss) var dismiss

    /// Whether the Add-rival scanner sheet is presented.
    @State var scanning = false
    /// `sheet(item:)` needs Identifiable; identity = the link itself.
    struct NearbyPayload: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    /// The Nearby sheet's payload, built ONCE when the button is tapped.
    /// Building it in the sheet's ViewBuilder instead published from within
    /// a view update (refreshFromCloud mutates the scoreboard) and looped.
    @State var nearbyURL: NearbyPayload?
    private let identityStore = ShareIdentityStore()

    enum Tab: Hashable { case rivals, squads }
    @State var tab: Tab = .rivals
    /// The keyboard cursor: the Tab-focused zone plus, in the rows zone, the
    /// focused row of the CURRENT tab's list (reset on tab switch). Inert off
    /// macOS.
    @State var keys = KeyCursor<KeyZone>()
    /// Fired to activate the card's focused control (see ShareCardView).
    @State var cardActivate = Pulse()
    /// Fired to flip the sync toggle (see SyncFooterControl).
    @State var syncActivate = Pulse()
    /// Whether the share card has a built link — the card reports it, and the
    /// card-action zones follow it (no reachable zones for hidden buttons).
    @State var cardHasLink = false
    /// The Squads tab's new-squad field (keyboard zone entry starts editing).
    @FocusState var newSquadFocused: Bool

    /// Tab-cyclable zones, in visual order. The card's action zones exist
    /// only while the card has a link; the new-squad field only on Squads.
    enum KeyZone: CaseIterable {
        case name, career, nearby, shareLink, qr, tabs, addRival, newSquad, rows, sync
    }

    /// The open sheet's subject, or nil: editing (rival/group detail) vs
    /// comparing (head-to-head). One of each pair is live at a time.
    @State var editingRival: Friend?
    @State var comparingRival: Friend?
    @State var editingGroup: FriendGroup?
    @State var comparingGroup: FriendGroup?
    @State private var newGroupName = ""  // the Squads tab's new-squad field

    /// Rivals alphabetical; ties broken by key for a stable order.
    var rivals: [Friend] {
        friends.friends.sorted {
            let byName = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            if byName != .orderedSame { return byName == .orderedAscending }
            return $0.publicKey.lexicographicallyPrecedes($1.publicKey)
        }
    }

    var body: some View {
        chrome
            .escDismisses { dismiss() }
            .appearanceSheet(isPresented: $scanning, settings) {
                AddFriendSheet { url in
                    scanning = false
                    dismiss()  // close the Mess hall so the prompt shows at root
                    onScanned?(url)
                }
            }
            .appearanceSheet(item: $nearbyURL, settings) { payload in
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
            .appearanceSheet(item: $editingRival, settings) {
                FriendDetailView(friend: $0, friends: friends)
            }
            .appearanceSheet(item: $comparingRival, settings) { rival in
                HeadToHeadView(
                    scoreboard: scoreboard, opponentName: rival.displayName,
                    result: FriendRanking.headToHead(with: rival, scoreboard: scoreboard),
                    // Career comparison only when this rival opted to share it.
                    career: rival.career.map {
                        (yours: SharePayloadBuilder.career(from: scoreboard), theirs: $0)
                    },
                    dailyRows: FriendRanking.dailyRows(
                        yours: dailyStore.displayRecords, theirs: rival.dailies),
                    onPlay: play)
            }
            .appearanceSheet(item: $editingGroup, settings) {
                GroupEditView(group: $0, friends: friends)
            }
            .appearanceSheet(item: $comparingGroup, settings) { group in
                HeadToHeadView(
                    scoreboard: scoreboard, opponentName: group.name,
                    result: FriendRanking.headToHead(
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

    #if os(macOS)
    /// The macOS header: the share card, then the tab picker sharing a row with
    /// the icon-only Add-rival door to the scanner. (iOS uses `collapsingContent`
    /// — the card scrolls, the tab bar pins — so this is Mac-only.)
    private var shareHeader: some View {
        VStack(spacing: 8) {
            ShareCardView(
                scoreboard: scoreboard, settings: settings, dailyStore: dailyStore,
                onNearby: { nearbyURL = currentShareURL().map(NearbyPayload.init) },
                keyFocus: cardKeyFocus, activate: cardActivate,
                hasLink: $cardHasLink)
            HStack(spacing: 10) {
                tabPicker.modifier(zoneRing(.tabs))
                Button {
                    scanning = true
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                }
                .buttonStyle(.bordered)
                .modifier(zoneRing(.addRival))
                .accessibilityLabel(Text("Add rival", bundle: .module))
            }
        }
    }
    #endif

    #if os(iOS)
    /// The whole sheet as ONE scroll: the share card is a plain first row that
    /// scrolls away, and the Rivals/Squads tab bar + scan button is a PINNED
    /// section header (`.plain` list style pins headers). This reclaims the
    /// space a fixed header stole in landscape, and shows more of the list once
    /// you scroll past the card in portrait too.
    @ViewBuilder private var collapsingContent: some View {
        List {
            Section {
                ShareCardView(
                    scoreboard: scoreboard, settings: settings, dailyStore: dailyStore,
                    onNearby: { nearbyURL = currentShareURL().map(NearbyPayload.init) },
                    keyFocus: cardKeyFocus, activate: cardActivate,
                    hasLink: $cardHasLink
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .listRowSeparator(.hidden)
            }
            Section {
                switch tab {
                case .rivals:
                    if rivals.isEmpty {
                        emptyRivals.listRowSeparator(.hidden)
                    } else {
                        rivalRows
                    }
                case .squads:
                    groupRows
                }
            } header: {
                pinnedTabBar
            }
        }
        .listStyle(.plain)
        .modifier(TightSectionSpacing())
    }

    /// The pinned sub-bar: the Rivals/Squads picker + the scan door. Styled as a
    /// header (edge-to-edge, opaque backing) so it reads as chrome, not a row.
    private var pinnedTabBar: some View {
        HStack(spacing: 10) {
            tabPicker.modifier(zoneRing(.tabs))
            Button {
                scanning = true
            } label: {
                Image(systemName: "qrcode.viewfinder")
            }
            .buttonStyle(.bordered)
            .modifier(zoneRing(.addRival))
            .accessibilityLabel(Text("Add rival", bundle: .module))
        }
        .padding(.vertical, 6)
        .textCase(nil)
        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
    }

    private var emptyRivals: some View {
        ListEmptyState(
            icon: "person.2", title: "No rivals yet.",
            detail: "Add a rival's scores by scanning their QR code or opening a share link.")
    }

    /// Collapse the default gap `.plain` leaves between the card section and the
    /// pinned tab bar. `.listSectionSpacing` is iOS 17+; a no-op below that (the
    /// gap is a cosmetic nicety, not a functional issue).
    private struct TightSectionSpacing: ViewModifier {
        func body(content: Content) -> some View {
            if #available(iOS 17.0, *) {
                content.listSectionSpacing(0)
            } else {
                content
            }
        }
    }
    #endif

    /// The signed share link, through the same gate chain the card uses —
    /// but with the FULL daily history (Nearby has no scan budget).
    func currentShareURL() -> URL? {
        SharePayloadBuilder.currentURL(
            scoreboard: scoreboard, settings: settings, identityStore: identityStore,
            dailyStore: dailyStore, dailyDays: nil)
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
            ListEmptyState(
                icon: "person.2", title: "No rivals yet.",
                detail: "Add a rival's scores by scanning their QR code or opening a share link.")
        } else {
            List { rivalRows }
        }
    }

    /// The rival rows, as List content (shared by the macOS List and the iOS
    /// collapsing List). Empty state is handled by the caller.
    @ViewBuilder private var rivalRows: some View {
        ForEach(Array(rivals.enumerated()), id: \.element.id) { index, rival in
            // Tap = compare (the primary action); trailing pencil = edit.
            CompareEditRow(
                compare: {
                    focusRow(index)
                    comparingRival = rival
                },
                edit: {
                    focusRow(index)
                    editingRival = rival
                }
            ) {
                FriendRow(friend: rival, groupNames: groupNames(for: rival))
            }
            .modifier(keyFocusRing(index))
        }
        .onDelete { offsets in
            offsets.map { rivals[$0].publicKey }.forEach { friends.delete($0) }
        }
    }

    /// A rival's group names, resolved from their membership ids via the catalog.
    private func groupNames(for friend: Friend) -> [String] {
        friend.groups.compactMap { id in friends.groups.first { $0.id == id }?.name }
    }

    // MARK: Groups tab

    @ViewBuilder private var groupsList: some View {
        List { groupRows }
    }

    /// The squads rows, as List content (shared by the macOS List and the iOS
    /// collapsing List): the create-squad field, then the squads.
    @ViewBuilder private var groupRows: some View {
        // Create a group, then jump straight into editing it (name + add members).
        HStack(spacing: 8) {
            TextField(text: $newGroupName) { Text("New squad", bundle: .module) }
                .textFieldStyle(.roundedBorder)
                .focused($newSquadFocused)
                .onSubmit(createGroup)
            Button(action: createGroup) { Text("Add", bundle: .module) }
                .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .modifier(zoneRing(.newSquad))

        if friends.groups.isEmpty {
            Text("No squads yet — create one above.", bundle: .module)
                .font(.callout).foregroundStyle(.secondary)
        } else {
            ForEach(Array(friends.groups.enumerated()), id: \.element.id) { index, group in
                // Tap = compare vs the group's best; pencil = edit (name/members/delete).
                CompareEditRow(
                    compare: {
                        focusRow(index)
                        comparingGroup = group
                    },
                    edit: {
                        focusRow(index)
                        editingGroup = group
                    },
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

extension MessHallView {
    private func createGroup() {
        guard let group = friends.createGroup(named: newGroupName) else { return }
        newGroupName = ""
        editingGroup = group  // open the edit view so you can add rivals right away
    }

    // MARK: Chrome

    // No macOS minHeight: the sheet's floor derives from the content's own
    // minimums (a fixed floor below them clipped both ends); the list carries
    // an explicit ideal because a List's ideal height resolves near ZERO
    // under a sheet's unbounded proposal.
    private var chrome: some View {
        SheetScaffold(
            title: "Mess hall", macMinWidth: 600, macIdealHeight: 600,
            content: {
                #if os(iOS)
                collapsingContent
                #else
                shareHeader
                tabContent.frame(minHeight: 180, idealHeight: 300)
                #endif
            },
            macFooter: {
                #if os(macOS)
                SyncFooterControl(
                    settings: settings, scoreboard: scoreboard,
                    keyFocused: keys.zone == .sync, activate: syncActivate)
                #endif
            },
            macBackground: {
                #if os(macOS)
                // Arrows move the row focus, Return compares, E edits, ⌘1/⌘2
                // switch tabs, Esc closes. Yields while a name field is being
                // edited, so typing is never hijacked.
                KeyCatcher(onKey: handleKey, yieldsToTextFields: true)
                #endif
            },
            iosBottomBar: {
                #if os(iOS)
                // Sync lives here too, not only in the Record — the Mess hall
                // is where sync questions arise; the control is self-contained.
                SyncFooterControl(settings: settings, scoreboard: scoreboard)
                #endif
            })
    }
}

extension MessHallView {
    /// A list row's keyboard-focus ring (inert off macOS); at inset 2 it hugged.
    func keyFocusRing(_ index: Int) -> FocusRing {
        FocusRing(focused: keys.zone == .rows && keys.index == index, inset: 6)
    }

    /// The Tab-focus ring for a header zone (inert off macOS).
    func zoneRing(_ zone: KeyZone) -> FocusRing {
        FocusRing(focused: keys.zone == zone, inset: 2)
    }

    /// A tapped row takes the keyboard focus with it, so the arrows resume
    /// from the clicked row when the sheet closes.
    func focusRow(_ index: Int) {
        keys.enter(.rows)
        keys.index = index
    }

    /// The card control the current zone maps to (ring + activation target).
    var cardKeyFocus: ShareCardView.KeyFocus? {
        switch keys.zone {
        case .name: return .name
        case .career: return .career
        case .nearby: return .nearby
        case .shareLink: return .shareLink
        case .qr: return .qr
        default: return nil
        }
    }
}
