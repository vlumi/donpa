import DonpaCore
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// The high-score table: clears + best time per config. Basic always shows;
/// Grid/Hive appear once played (to avoid rows of empties). Stored by geometry.
struct ScoreboardView: View {
    @ObservedObject var scoreboard: Scoreboard
    @ObservedObject var settings: Settings
    /// Presenting window size, so the sheet grows with it. `.zero` → use the screen.
    var available: CGSize = .zero
    /// The config the player is currently on, so its row gets a persistent "you are
    /// here" marker and the filter seeds to its family/edges. nil when opened from
    /// the title (browsing).
    var currentConfig: GameConfig?
    /// The current config's storage key — the scroll anchor for the "jump to current"
    /// behaviour.
    private var currentConfigKey: String? { currentConfig?.storageKey }
    /// Start a fresh game on a config (the row expansion's "New game on this board").
    /// The host wires this to begin the game and dismiss the sheet. nil = no button.
    var onPlay: ((GameConfig) -> Void)?
    /// Route a scanned rival URL (from the Share sheet's Scan tab) into the receive
    /// flow: the host closes the scoreboard and hands it to the root classify/prompt
    /// path. nil = scanning disabled.
    var onReceiveURL: ((URL) -> Void)?
    /// Open the rivals list. The host dismisses this sheet and presents the list at the
    /// root (so its sub-sheets don't stack on the scoreboard). nil = no rivals button.
    var onFriends: (() -> Void)?
    /// Tracked friends, for the per-config rival comparison. No friends → no
    /// comparison shown, rows behave exactly as before.
    @ObservedObject var friends: FriendsStore
    /// The group to compare against, or nil for all friends (the group filter). Not
    /// `private`: the rival-scope control lives in a `ScoreboardView` extension in
    /// another file (ScoreboardRivals) — Swift `private` is file-scoped.
    @State var rivalGroupID: String?
    // Not `private`: the iOS toolbar lives in a `ScoreboardView` extension in another
    // file (ScoreboardToolbar) and drives these — Swift `private` is file-scoped.
    @Environment(\.dismiss) var dismiss
    @State var sharing = false

    /// High-scores filter: one Family × Edges leaf at a time (Basic ignores edges).
    /// View-only state — a browsing choice, not persisted. Seeded in `onAppear` to
    /// the config being played, so opening in-game lands on the relevant list.
    @State private var filterFamily: BoardFamily = .basic
    @State private var filterEdges: BoardEdges = .flat
    /// The one config expanded to its stat-block (accordion — at most one open).
    @State private var expandedKey: String?

    var body: some View {
        sheetChrome
            .onAppear(perform: seedFilterFromCurrent)
            .sheet(isPresented: $sharing) {
                ShareScoresView(
                    scoreboard: scoreboard, settings: settings,
                    onScanned: onReceiveURL.map { route in
                        { url in
                            sharing = false
                            dismiss()  // close the scoreboard so the prompt shows at root
                            route(url)
                        }
                    })
            }
    }

    /// iOS: a NavigationStack with Reset / Done nav-bar items over the list. macOS:
    /// inline title + bottom buttons, window-sized.
    @ViewBuilder private var sheetChrome: some View {
        #if os(iOS)
        NavigationStack {
            content
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                // Sync control pinned to the bottom, not buried under the stats.
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 0) {
                        Divider()
                        SyncFooterControl(settings: settings, scoreboard: scoreboard)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                    .background(.bar)
                }
                .navigationTitle(Text("Service Record", bundle: .module))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { iOSToolbar }
        }
        #else
        VStack(spacing: 16) {
            Text("Service Record", bundle: .module).font(.title2.bold())

            content  // sizes to content; capped by the sheet's maxHeight below

            Divider()
            HStack(spacing: 12) {
                SyncFooterControl(settings: settings, scoreboard: scoreboard)
                Spacer()
                Button {
                    sharing = true
                } label: {
                    Label {
                        Text("Share", bundle: .module)
                    } icon: {
                        Image(systemName: "qrcode")
                    }
                }
                if let onFriends {
                    Button(action: onFriends) {
                        Label {
                            Text("Rivals", bundle: .module)
                        } icon: {
                            Image(systemName: "person.2")
                        }
                    }
                }
                Button {
                    dismiss()
                } label: {
                    Text("Done", bundle: .module)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Self.rowInset)  // align with the row text
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 14)  // rest of the side margin lives on the rows
        // Width is driven firmly (else the sheet shrinks to content and won't widen
        // for two columns). Height is a cap only — the sheet sizes to content and
        // only grows to `sheetHeight` (then the scores column scrolls).
        .frame(width: sheetWidth)
        .frame(maxHeight: sheetHeight)
        #endif
    }

    #if os(macOS)
    /// Container to bound against: the presenting window, or the screen as a
    /// fallback before its size is known.
    private var container: CGSize {
        if available != .zero { return available }
        let h = NSScreen.main?.visibleFrame.height ?? 800
        let w = NSScreen.main?.visibleFrame.width ?? 1000
        return CGSize(width: w, height: h)
    }

    /// Tall in a big window, short in a small one, bounded so it never overflows.
    private var sheetHeight: CGFloat { min(1100, max(380, container.height * 0.94)) }
    /// Cap past the two-column breakpoint so a roomy window gives two columns; a
    /// small window still shrinks to fit.
    private var sheetWidth: CGFloat { min(820, max(300, container.width * 0.9)) }
    #endif

    /// Gutter at the right of the table so the scroll indicator sits clear of the
    /// rows and their dividers.
    private static let scrollbarGutter: CGFloat = 16
    // Not `private`: referenced by the ScoreboardRivals extension (another file).
    /// Horizontal breathing room inside each row (and the record-highlight band).
    static let rowInset: CGFloat = 10

    /// One scrolling sheet, the same law at every width (the sheet scrolls, so a big
    /// screen just shows more without a distinct pinned-column layout): the global
    /// Career, the Family/Edges filter, then the filtered high-score list — its rows
    /// expandable to that config's own stat-block. Width only tunes column counts
    /// inside the blocks, not the flow.
    @ViewBuilder private var content: some View {
        anchoredScroll {
            VStack(alignment: .leading, spacing: 24) {
                careerSection
                scoresSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, Self.scrollbarGutter)
        }
    }

    /// A ScrollView that, when opened in-game (`currentConfigKey` set), jumps the
    /// current config's row into view — so you land on the board you're playing.
    /// Opened from the title (key nil) it stays at the top for plain browsing.
    @ViewBuilder private func anchoredScroll<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        let inner = content()
        ScrollViewReader { proxy in
            ScrollView {
                inner
            }
            .onAppear {
                guard let key = currentConfigKey else { return }
                // A beat after layout so the target row exists before we scroll.
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(key, anchor: .center)
                    }
                }
            }
            // Expanding a row scrolls it into view — otherwise expanding the LAST
            // row opens content that's off-screen below the fold (and there may be
            // no layout shift to nudge it up). A beat later so the taller row has
            // laid out before we scroll to it.
            .onChangeCompat(of: expandedKey) { key in
                guard let key else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(key, anchor: .center)
                    }
                }
            }
        }
    }

    /// Width for the column decision: the sheet width (macOS) or presenting window
    /// (iOS).
    private var layoutWidth: CGFloat {
        #if os(macOS)
        return sheetWidth
        #else
        return available.width
        #endif
    }

    /// Two-column stat blocks above this width, one column below.
    private static let twoColumnMinWidth: CGFloat = 520

    /// Lifetime totals across every config — the global Career, drawn with the same
    /// `StatBlock` as a single config's expansion so the two read alike. Deliberately
    /// no win rate: raw, neutral counts (a win% only discourages).
    @ViewBuilder private var careerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Tour of Duty")
            let career = StatFigures(career: Array(scoreboard.displayRecords.values))
            if career.hasPlayed {
                StatBlock(
                    figures: career, twoColumnWidth: Self.twoColumnMinWidth,
                    rowInset: Self.rowInset)
            } else {
                Text("Play a game to start your career stats.", bundle: .module)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
    }

    /// The filtered high-score list: a Family/Edges picker, then the one leaf's
    /// configs as expandable rows.
    @ViewBuilder private var scoresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Commendations")
            filterControls
            if !friends.friends.isEmpty { rivalScopeControl }
            leafRows
        }
    }

    /// Family + Edges segmented controls (Edges disabled on Basic, which has no
    /// edges). Selecting either collapses any open expansion, since the list changes.
    /// `ViewThatFits` places them side by side with a gap when the width allows,
    /// stacked when narrow — measuring the real available width (a computed
    /// breakpoint mis-fired on the Mac sheet).
    @ViewBuilder private var filterControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 20) {
                familyPicker
                edgesPicker
            }
            .frame(minWidth: Self.twoColumnMinWidth)
            VStack(alignment: .leading, spacing: 10) {
                familyPicker
                edgesPicker
            }
        }
        .labelsHidden()
        .padding(.horizontal, Self.rowInset)
    }

    private var familyPicker: some View {
        SegmentedGlyphPicker(
            values: BoardFamily.allCases, selection: $filterFamily,
            glyph: { .family($0) }, label: { $0.label },
            onChange: { expandedKey = nil })
    }

    private var edgesPicker: some View {
        SegmentedGlyphPicker(
            values: BoardEdges.allCases, selection: $filterEdges,
            glyph: { .edges($0) }, label: { $0.label },
            onChange: { expandedKey = nil }
        )
        .disabled(filterFamily == .basic)
        .opacity(filterFamily == .basic ? 0.4 : 1)
    }

    /// The selected Family × Edges leaf, every size × rank shown (played or not).
    /// Pinned to full width so the sheet never resizes when switching between a
    /// family with long labels (Basic's "Intermediate") and short ones (Grid "XS").
    @ViewBuilder private var leafRows: some View {
        let edges: BoardEdges = filterFamily == .basic ? .flat : filterEdges
        let configs = GameConfig.configs(family: filterFamily, edges: edges)
        let rivals = RivalRanking.rivals(from: friends, group: rivalGroupID)
        VStack(spacing: 0) {
            columnHeader
            ForEach(configs, id: \.self) { config in
                ScoreRow(
                    scoreboard: scoreboard, config: config,
                    currentConfigKey: currentConfigKey, rowInset: Self.rowInset,
                    isExpanded: expandedKey == config.storageKey,
                    onToggle: { toggleExpanded(config.storageKey) },
                    onPlay: onPlay.map { play in { play(config) } },
                    rivals: rivals, yourName: settings.shareName
                )
                .id(config.storageKey)  // scroll anchor for the current-config jump
                if config != configs.last { Divider() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The list's column titles (Cleared / Best % / Best), matching `ScoreRow`.
    private var columnHeader: some View {
        HStack {
            Spacer()
            Text("Cleared", bundle: .module).font(.caption).foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
            Text("Best %", bundle: .module).font(.caption).foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
            Text("Best", bundle: .module).font(.caption).foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, Self.rowInset)
    }

    /// Accordion toggle: open the tapped row, closing any other.
    private func toggleExpanded(_ key: String) {
        expandedKey = (expandedKey == key) ? nil : key
    }

    /// Seed the filter to the config being played (so opening in-game shows its
    /// list), else leave the Basic default for plain browsing from the title.
    private func seedFilterFromCurrent() {
        guard let config = currentConfig else { return }
        filterFamily = config.family
        filterEdges = config.edges
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title, bundle: .module)
            .font(.title3.bold())
            .padding(.horizontal, Self.rowInset)
    }

}
