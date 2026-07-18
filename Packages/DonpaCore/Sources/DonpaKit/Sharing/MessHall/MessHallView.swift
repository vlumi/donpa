import DonpaCore
import SwiftUI

/// The **Mess hall** — where units mingle: your share card over your rivals,
/// one social screen (FI *Sotku*, JA 食堂) on one `FriendsStore`. Tapping a
/// row COMPARES you head-to-head; a trailing pencil edits (alias/removal).
/// Sorted alphabetically. Read-only over the store except through its
/// methods — the display-merge invariant means removing an entry just drops
/// its data.
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

    /// The keyboard cursor: the Tab-focused zone plus, in the rows zone, the
    /// focused rival row. Inert off macOS.
    @State var keys = KeyCursor<KeyZone>()
    /// Fired to activate the card's focused control (see ShareCardView).
    @State var cardActivate = Pulse()
    /// Fired to flip the sync toggle (see SyncFooterControl).
    @State var syncActivate = Pulse()
    /// Whether the share card has a built link — the card reports it, and the
    /// card-action zones follow it (no reachable zones for hidden buttons).
    @State var cardHasLink = false

    /// Tab-cyclable zones, in visual order. The card's action zones exist
    /// only while the card has a link.
    enum KeyZone: CaseIterable {
        case name, career, nearby, rows, sync
    }

    /// The open sheet's subject, or nil: editing (rival/group detail) vs
    /// comparing (head-to-head). One of each pair is live at a time.
    @State var editingRival: Friend?
    @State var comparingRival: Friend?

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
    }

    /// A head-to-head row's play tapped: collapse this whole surface (the sheet
    /// stack folds with it) and hand the board to the host to start the game.
    private func play(_ config: GameConfig) {
        comparingRival = nil
        dismiss()
        onPlay?(config)
    }

    // MARK: Share / scan header

    #if os(macOS)
    /// The macOS header: just the share card. (iOS uses `collapsingContent` —
    /// the card scrolls with the list.)
    private var shareHeader: some View {
        ShareCardView(
            scoreboard: scoreboard, settings: settings, dailyStore: dailyStore,
            onNearby: { nearbyURL = currentShareURL().map(NearbyPayload.init) },
            keyFocus: cardKeyFocus, activate: cardActivate,
            hasLink: $cardHasLink)
    }
    #endif

    #if os(iOS)
    /// The whole sheet as ONE scroll: the share card is a plain first row that
    /// scrolls away above the rivals list.
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
                if rivals.isEmpty {
                    emptyRivals.listRowSeparator(.hidden)
                } else {
                    rivalRows
                }
            }
        }
        .listStyle(.plain)
        .modifier(TightSectionSpacing())
    }

    private var emptyRivals: some View {
        ListEmptyState(
            icon: "person.2", title: "No rivals yet.",
            detail: "Swap score cards in person with Nearby to add your first rival.")
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

    // MARK: Rivals tab

    @ViewBuilder var rivalsList: some View {
        if rivals.isEmpty {
            ListEmptyState(
                icon: "person.2", title: "No rivals yet.",
                detail: "Swap score cards in person with Nearby to add your first rival.")
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
                FriendRow(friend: rival, groupNames: [])
            }
            .modifier(keyFocusRing(index))
        }
        .onDelete { offsets in
            offsets.map { rivals[$0].publicKey }.forEach { friends.delete($0) }
        }
    }

}

extension MessHallView {
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
                rivalsList.frame(minHeight: 180, idealHeight: 300)
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
                // Arrows move the row focus, Return compares, E edits, Esc
                // closes. Yields while a name field is being edited, so typing
                // is never hijacked.
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
        default: return nil
        }
    }
}
