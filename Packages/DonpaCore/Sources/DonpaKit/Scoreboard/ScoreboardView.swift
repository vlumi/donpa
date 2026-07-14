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
    /// The earned-feat store behind the Decorations grid. Optional so title-
    /// screen previews and tests don't have to build the sync stack.
    var achievements: AchievementStore?
    /// Presenting window size, so the sheet grows with it. `.zero` → use the screen.
    var available: CGSize = .zero
    /// Progressive gating — hides the per-row play button on locked configs
    /// (the row itself stays: locked is visible, never hidden).
    var gates = UnlockGates.open
    /// The config the player is currently on, so its row gets a persistent "you are
    /// here" marker and the filter seeds to its family/edges. nil when opened from
    /// the title (browsing).
    var currentConfig: GameConfig?
    /// The current config's storage key — the scroll anchor for the "jump to current"
    /// behaviour.
    var currentConfigKey: String? { currentConfig?.storageKey }
    /// Start a fresh game on a config (the row expansion's "New game on this board").
    /// The host wires this to begin the game and dismiss the sheet. nil = no button.
    var onPlay: ((GameConfig) -> Void)?
    /// Open the Mess hall (the social screen) — the "Manage rivals" cross-link by
    /// the rival-scope control. The host dismisses this sheet and presents the Mess
    /// hall at the root. nil = no cross-link.
    var onMessHall: (() -> Void)?
    /// No friends → no rival comparison; rows behave as before.
    @ObservedObject var friends: FriendsStore
    // Throughout: state that sibling-file ScoreboardView extensions drive
    // (Keyboard/Toolbar/Rivals/Scroll) is internal, not `private` — Swift
    // `private` is file-scoped.

    /// Game Center reporting (the Decorations footer's toggle drives it).
    @ObservedObject var gameCenter: GameCenterReporter
    /// The group to compare against, or nil for all friends (the group filter).
    @State var rivalGroupID: String?
    @Environment(\.dismiss) var dismiss

    /// High-scores filter: one Family × Edges leaf at a time (Basic ignores edges).
    /// View-only state — a browsing choice, not persisted. Seeded in `onAppear` to
    /// the config being played, so opening in-game lands on the relevant list.
    @State var filterFamily: BoardFamily = .basic
    @State var filterEdges: BoardEdges = .flat
    /// The one config expanded to its stat-block (accordion — at most one open).
    @State var expandedKey: String?
    /// The keyboard-focused row's config key — STRING-keyed satellite state
    /// beside `keys` (it self-heals across filter changes where an index
    /// couldn't). Nil until the first arrow press; inert off macOS.
    @State var keyRowKey: String?
    /// The Tab-focused zone plus, in the medals zone, the focused medal.
    @State var keys = KeyCursor<KeyZone>()
    /// Fired to flip the sync toggle from the keyboard (see SyncFooterControl).
    @State var syncActivate = Pulse()
    /// The tapped/keyboard-selected medal whose detail line shows under the
    /// grid. Hoisted from DecorationsSection so the keyboard can drive it.
    @State var selectedMedal: AchievementID?

    /// The sheet's Tab-cyclable control zones, in visual order. `career` is a
    /// read-only scroll anchor (stats have nothing to operate); `edges` is
    /// skipped while the family has no edges axis.
    enum KeyZone: CaseIterable {
        case career, breakdown, medals, family, edges, rivals, manage, rows, sync
    }

    /// The Breakdown block's metric, hoisted so the keyboard can flip it.
    @State var breakdownMetric: PlayDistribution.Metric = .playtime
    /// Grows the header's stat columns with Dynamic Type — must match
    /// `ScoreRow.columnScale` so the table stays aligned.
    @ScaledMetric(relativeTo: .body) private var columnScale: CGFloat = 1

    var body: some View {
        sheetChrome
            .escDismisses { dismiss() }
            .onAppear(perform: seedFilterFromCurrent)
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
                SyncFooterControl(
                    settings: settings, scoreboard: scoreboard,
                    keyFocused: keys.zone == .sync, activate: syncActivate)
                Spacer()
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
        // Arrow/Return/⌘1-4/E/P keyboard driving — see ScoreboardKeyboard.
        .background(KeyCatcher { handleKey($0) })
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
                    .id("zone.career")
                    .modifier(zoneRing(.career))
                if let achievements {
                    DecorationsSection(
                        achievements: achievements, records: scoreboard.displayRecords,
                        rowInset: Self.rowInset, selected: $selectedMedal,
                        keyFocusIndex: medalFocusIndex,
                        headerKeyFocused: keys.zone == .medals && keys.index == nil,
                        collapsed: $settings.medalsCollapsed,
                        gcEnabled: Binding(
                            get: { gameCenter.enabled },
                            set: { gameCenter.setEnabled($0) }),
                        gcKeyFocused: keys.zone == .medals
                            && keys.index == AchievementID.allCases.count
                    )
                    .id("zone.medals")
                    .onChangeCompat(of: selectedMedal) { followMedalSelection($0) }
                }
                scoresSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, Self.scrollbarGutter)
        }
    }

    /// Whether a row carries the keyboard-focus ring (macOS arrow navigation).
    private func keyFocused(_ config: GameConfig) -> Bool {
        keys.zone == .rows && keyRowKey == config.storageKey
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
                PlayDistributionView(
                    scoreboard: scoreboard, rowInset: Self.rowInset,
                    metric: $breakdownMetric, keyFocused: breakdownKeyFocused
                )
                .padding(.top, 8)
                .id("zone.breakdown")
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
            if !friends.friends.isEmpty { rivalScopeControl.id("zone.rivals") }
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
                // Four families vs two edges: the family picker keeps its roomy
                // glyph-beside-label segments and takes ALL the width the hugged
                // edges toggle leaves (well over half the row).
                familyPicker(stacked: false)
                // Same-line layout: Basic keeps the edges SLOT (invisible) so the
                // family picker doesn't jump between half- and full-width.
                edgesPicker(placeholderWhenBasic: true)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(minWidth: Self.twoColumnMinWidth)
            VStack(alignment: .leading, spacing: 10) {
                // Narrow (phone) rows: even alone on its row, four side-by-side
                // labels truncate — stack each segment's glyph above its label.
                familyPicker(stacked: true)
                // Stacked layout: drop the row outright — a blank reserved line
                // would just read as a layout bug.
                edgesPicker(placeholderWhenBasic: false)
            }
        }
        .labelsHidden()
        .padding(.horizontal, Self.rowInset)
        .id("zone.filters")
    }

    private func familyPicker(stacked: Bool) -> some View {
        SegmentedGlyphPicker(
            values: BoardFamily.allCases, selection: $filterFamily,
            glyph: { .family($0) }, label: { $0.label },
            onChange: { expandedKey = nil },
            stacked: stacked
        )
        .modifier(zoneRing(.family))
    }

    /// Gone for Basic and Drills (neither has an edges axis; a ghosted control
    /// begs "why can't I press this?") — but on the same-line layout the SLOT is
    /// preserved invisibly, so hiding it doesn't reflow the family picker.
    @ViewBuilder private func edgesPicker(placeholderWhenBasic: Bool) -> some View {
        if filterFamily == .grid || filterFamily == .hive {
            edgesPickerControl
        } else if placeholderWhenBasic {
            edgesPickerControl.hidden()
        }
    }

    private var edgesPickerControl: some View {
        SegmentedGlyphPicker(
            values: BoardEdges.allCases, selection: $filterEdges,
            glyph: { .edges($0) }, label: { $0.label },
            onChange: { expandedKey = nil }
        )
        .modifier(zoneRing(.edges))
    }

    /// The Tab-focus ring for a filter zone (inert off macOS).
    func zoneRing(_ zone: KeyZone) -> FocusRing {
        FocusRing(focused: keys.zone == zone, inset: 3)
    }

    /// The medal the keyboard is browsing (ring in the grid), while the medals
    /// zone is active.
    private var medalFocusIndex: Int? {
        keys.zone == .medals ? keys.index : nil
    }

    /// A tapped medal takes the keyboard focus with it (selection is set by
    /// both the tap and the keyboard; re-entering the same zone is harmless).
    func followMedalSelection(_ id: AchievementID?) {
        guard let id, let i = AchievementID.allCases.firstIndex(of: id) else { return }
        keys.enter(.medals)
        keys.index = i
    }

    private var breakdownKeyFocused: Bool {
        keys.zone == .breakdown
    }

    /// The selected Family × Edges leaf, every size × rank shown (played or not),
    /// grouped by size with a full-clear subheader per group (see ScoreboardGroups).
    /// Pinned to full width so the sheet never resizes when switching between a
    /// family with long labels (Basic's "Intermediate") and short ones (Grid "XS").
    @ViewBuilder private var leafRows: some View {
        let edges: BoardEdges =
            filterFamily == .grid || filterFamily == .hive
            ? filterEdges : .flat
        let groups = Self.groups(family: filterFamily, edges: edges)
        let rivals = FriendRanking.rivals(from: friends, group: rivalGroupID)
        VStack(spacing: 0) {
            columnHeader
            ForEach(groups) { group in
                if let label = group.label {
                    groupHeader(label, standing: standing(for: group))
                }
                ForEach(group.configs, id: \.self) { config in
                    ScoreRow(
                        scoreboard: scoreboard, config: config,
                        currentConfigKey: currentConfigKey, rowInset: Self.rowInset,
                        isExpanded: expandedKey == config.storageKey,
                        isKeyFocused: keyFocused(config),
                        onToggle: {
                            toggleExpanded(config.storageKey)
                            // Click takes the keyboard focus with it, so the
                            // arrows resume from the clicked row.
                            keyRowKey = config.storageKey
                            keys.enter(.rows)
                        },
                        onPlay: gates.config(config)
                            ? onPlay.map { play in { play(config) } } : nil,
                        rivals: rivals, yourName: settings.shareName
                    )
                    .id(config.storageKey)  // scroll anchor for the current-config jump
                    if config != group.configs.last { Divider() }
                }
                // Basic only: Drills' group is also label-less, but a
                // cross-size Total is a deliberate non-goal there (practice,
                // not a ladder).
                if filterFamily == .basic, group.label == nil {
                    trifectaFooter(standing: standing(for: group))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The list's column titles (Cleared / Best % / Best), matching `ScoreRow` —
    /// the same scaled widths, and shrink-to-fit so a grown (or long localized)
    /// title never wraps or clips inside its column.
    private var columnHeader: some View {
        HStack {
            Spacer()
            Text("Cleared", bundle: .module).font(.caption).foregroundStyle(.secondary)
                .numericCell()
                .frame(width: ScoreColumns.cleared * columnScale, alignment: .trailing)
            Text("Best %", bundle: .module).font(.caption).foregroundStyle(.secondary)
                .numericCell()
                .frame(width: ScoreColumns.bestProgress * columnScale, alignment: .trailing)
            Text("Best", bundle: .module).font(.caption).foregroundStyle(.secondary)
                .numericCell()
                .frame(width: ScoreColumns.bestTime * columnScale, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, Self.rowInset)
    }

    /// Accordion toggle: open the tapped row, closing any other.
    func toggleExpanded(_ key: String) {
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
