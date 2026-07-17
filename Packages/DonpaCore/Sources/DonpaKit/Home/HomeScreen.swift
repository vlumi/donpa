import DonpaCore
import SwiftUI

/// The home hub — where the app launches and where Home returns to. A designed menu,
/// not a splash: the manga art as the masthead, a Continue card for the latest
/// in-progress board (expandable to all of them), a single New Game entry, and the
/// Service Record. Settings / About sit as round corner buttons. Replaces the old
/// TitleScreen (art-as-invisible-fork) and the ResumeListView sheet, both retired.
///
/// The army vocabulary calls this place the Barracks — your own unit's base — but
/// only in small doses (the in-game Home button's tooltip, the Mac menu item); the
/// art is the visible masthead, so the screen itself carries no title.
///
/// Two layouts by viewport shape (not platform): portrait phone stacks art over the
/// menu; anything wider puts the art beside it.
struct HomeScreen: View {
    @ObservedObject var settings: Settings
    /// In-progress games, newest played first — lightweight summaries, refreshed by
    /// the host when Home (re)appears. The host flushes saves synchronously before
    /// showing Home, so these reflect disk truth.
    let snapshots: [SaveStore.SaveSummary]
    /// Resume a saved board (the Continue card / a list row / the art when saves exist).
    let onContinue: (GameConfig) -> Void
    /// Open the New Game picker — the single, deliberate path to a fresh game.
    let onNewGame: () -> Void
    /// Today's board, or nil before the daily epoch.
    var dailyBoard: DailyChallenge.Board?
    /// Your standing on today's board (nil = not attempted).
    var dailyDay: DailyDayRecord?
    var dailyStreak: (current: Int, longest: Int) = (0, 0)
    var onDaily: () -> Void = {}
    var onDailyCalendar: () -> Void = {}
    let onScores: () -> Void
    /// Open the Mess hall — the social screen (share card, rivals, squads).
    let onMessHall: () -> Void
    let onSettings: () -> Void
    let onAbout: () -> Void
    let onHowTo: () -> Void
    /// Whether the title is the LIVE key surface (visible, nothing modal above).
    /// Home stays mounted under the game, so its key catcher must stand down
    /// whenever it isn't the one on screen.
    var keyboardActive: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    /// Whether the full in-progress list sheet is presented.
    @State var showAll = false
    /// The in-progress sheet's keyboard-focused row (arrow navigation); nil
    /// until the first arrow press, inert off macOS. See HomeContinue.
    @State var keyRowIndex: Int?
    /// The title's keyboard-focused menu item (Tab/arrow navigation); nil
    /// until the first press, inert off macOS.
    @State private var keys = KeyCursor<HomeKeyItem>()

    /// The title's keyboard-walkable items, in visual order (top-right corner
    /// utilities last).
    enum HomeKeyItem: CaseIterable {
        case continueLatest, inProgress, daily, dailyHistory, newGame, record, messHall
        case sound, howTo, settings, about
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Palette.resolved(for: colorScheme).pageBackground
                    .ignoresSafeArea()
                // Split by the window's own shape: a landscape window puts the menu
                // beside the art; a portrait one puts it below. (Not a platform or
                // width split — a tall Mac window stacks, a landscape phone doesn't.)
                if geo.size.width > geo.size.height {
                    landscapeLayout
                } else {
                    portraitLayout(width: geo.size.width)
                }
            }
            // Secondary utilities in the screen's top-right corner, as before.
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 8) {
                    roundButton(
                        label: settings.sound ? "Mute sound" : "Unmute sound",
                        id: "title.sound", action: { settings.sound.toggle() },
                        ring: homeRing(.sound)
                    ) {
                        Image(
                            systemName: settings.sound
                                ? "speaker.wave.2.fill" : "speaker.slash.fill"
                        )
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    }
                    roundButton(
                        label: "How to play", id: "title.howto", action: onHowTo,
                        ring: homeRing(.howTo)
                    ) {
                        Image(systemName: "questionmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    roundButton(
                        label: "Settings", id: "title.settings", action: onSettings,
                        ring: homeRing(.settings)
                    ) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    roundButton(
                        label: "About", id: "title.about", action: onAbout,
                        ring: homeRing(.about)
                    ) {
                        Image(systemName: "info")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(16)
            }
            .appearanceSheet(isPresented: $showAll, settings) { inProgressSheet }
            #if os(macOS)
            .background(
                // Conditional: Home stays mounted (opacity 0) under the game,
                // and an always-on catcher would eat the board's keys.
                keyboardActive ? KeyCatcher(onKey: handleHomeKey) : nil
            )
            #endif
        }
    }

    #if os(macOS)
    private var homeKeyItems: [HomeKeyItem] {
        HomeKeyItem.allCases.filter { item in
            switch item {
            case .continueLatest: return !snapshots.isEmpty
            case .inProgress: return snapshots.count > 1
            case .daily, .dailyHistory: return dailyBoard != nil
            default: return true
            }
        }
    }

    private func handleHomeKey(_ key: KeyCatcher.Key) {
        switch key {
        case .down, .tab, .right:
            keys.cycle(1, through: homeKeyItems)
        case .up, .backTab, .left:
            keys.cycle(-1, through: homeKeyItems)
        case .enter, .space:
            activateFocusedItem()
        default:
            // Esc clears deliberately; a mouse click clears because the
            // pointer took over (a clicked card re-navigates anyway).
            if key == .escape || key == .click { keys.enter(nil) }
        }
    }

    private func activateFocusedItem() {
        // A focused item can vanish under the ring (the Continue card after
        // its save is gone) — treat it as no focus rather than a dead Return.
        guard let item = keys.zone, homeKeyItems.contains(item) else {
            keys.enter(nil)
            // Nothing focused: Return is the title's primary action (the art
            // button) — run it HERE rather than via a .defaultAction shortcut.
            // A shortcut-activated button engages SwiftUI's focus engine,
            // which re-asserts first responder AFTER the board's claim and
            // left the arrows dead on continue-from-title.
            if let latest = snapshots.first { onContinue(latest.config) } else { onNewGame() }
            return
        }
        homeActions[item]?()
    }

    /// Dispatch table (not a switch — a pure mapping).
    private var homeActions: [HomeKeyItem: () -> Void] {
        var actions: [HomeKeyItem: () -> Void] = [
            .inProgress: { showAll = true },
            .newGame: onNewGame,
            .record: onScores,
            .messHall: onMessHall,
            .sound: { settings.sound.toggle() },
            .howTo: onHowTo,
            .settings: onSettings,
            .about: onAbout,
        ]
        if let latest = snapshots.first {
            actions[.continueLatest] = { onContinue(latest.config) }
        }
        if dailyBoard != nil {
            actions[.daily] = onDaily
            actions[.dailyHistory] = onDailyCalendar
        }
        return actions
    }
    #endif

    /// The keyboard-focus ring for a title item; a no-op ring off macOS.
    func homeRing(_ item: HomeKeyItem) -> FocusRing {
        FocusRing(focused: keys.zone == item, inset: 2)
    }

    // MARK: Layouts

    /// The menu column's width beside the art (landscape) / its cap below it
    /// (desktop portrait, where the art can spread wider above it).
    private static let menuWidth: CGFloat = 340
    private static let portraitMenuMaxWidth: CGFloat = 480
    /// Below this width a portrait window is phone-like: the art goes full width
    /// and the page scrolls. At/above it (a tall desktop window) nothing scrolls
    /// or clips — the art flexes into whatever height the menu leaves free.
    private static let phoneLikeMaxWidth: CGFloat = 500

    /// Portrait. Phone: one scrolling column, art full width (the masthead
    /// dominates; the menu scrolls into view on a short screen). Desktop portrait:
    /// the ART is the flexible element — it grows into a big window's spare height
    /// and shrinks on a small one, so the menu below is never cut off.
    @ViewBuilder private func portraitLayout(width: CGFloat) -> some View {
        if width < Self.phoneLikeMaxWidth {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    artButton
                    menu
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: 20) {
                artButton
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                menu
                    .frame(maxWidth: Self.portraitMenuMaxWidth)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Landscape (Mac, iPad, phone landscape): the art fills the height — it's the
    /// masthead, it should be BIG — with the menu hugging its content beside it,
    /// the pair centered as one group. The menu scrolls internally only when the
    /// expanded in-progress list outgrows the window.
    private var landscapeLayout: some View {
        HStack(spacing: 40) {
            artButton
            ViewThatFits(in: .vertical) {
                menu
                    .frame(width: Self.menuWidth)
                    // Optically a touch above dead center beside the tall art —
                    // true centering reads as sitting slightly low.
                    .padding(.bottom, 48)
                ScrollView(showsIndicators: false) {
                    menu
                        .frame(width: Self.menuWidth)
                }
            }
        }
        // Extra headroom keeps the menu clear of the corner utilities even on a
        // short window; the rest centers as a group.
        .padding(.top, 64)
        .padding([.horizontal, .bottom], 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The shared menu column: Continue (when there's anything to continue),
    /// New Game, Service Record, Mess hall.
    private var menu: some View {
        VStack(spacing: 12) {
            if let latest = snapshots.first {
                continueCard(latest: latest).modifier(homeRing(.continueLatest))
            }
            if let board = dailyBoard {
                dailyCard(board: board).modifier(homeRing(.daily))
            }
            newGameButton.modifier(homeRing(.newGame))
            recordButton.modifier(homeRing(.record))
            messHallButton.modifier(homeRing(.messHall))
        }
    }

    // MARK: Actions

    /// The single path to a fresh game: the full picker, deliberately — no quick-start
    /// presets anywhere; the picker is where the families/sizes/densities live.
    private var newGameButton: some View {
        Button(action: onNewGame) {
            Label {
                Text("New game", bundle: .module)
            } icon: {
                Image(systemName: "plus")
            }
            .font(.title3.weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.accentColor, in: Capsule())
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.newGame")
    }

    private var recordButton: some View {
        Button(action: onScores) {
            HStack(spacing: 10) {
                MangaIcon(symbol: .medal, size: 30, tint: .primary)
                Text("Service Record", bundle: .module)
                    .font(.body.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.primary.opacity(0.06))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("High Scores", bundle: .module))
        .accessibilityIdentifier("title.highScores")
    }

    private var messHallButton: some View {
        Button(action: onMessHall) {
            HStack(spacing: 10) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 30)
                Text("Mess hall", bundle: .module)
                    .font(.body.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.primary.opacity(0.06))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("title.messHall")
    }

    /// Small round overlay button for a secondary corner action (as on the old title).
    private func roundButton<Icon: View>(
        label: LocalizedStringKey, id: String, action: @escaping () -> Void,
        ring: FocusRing? = nil,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button(action: action) {
            icon()
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.55), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .modifier(ring ?? FocusRing(focused: false, inset: 0))
        .accessibilityLabel(Text(label, bundle: .module))
        .accessibilityIdentifier(id)
    }

    // MARK: Formatting

    /// `m:ss` elapsed, matching the in-game timer's larger form.
    static func clock(_ centiseconds: Int) -> String {
        let seconds = max(0, centiseconds / 100)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

}

// MARK: Masthead art

extension HomeScreen {

    /// The manga splash. Tappable as a shortcut for the PRIMARY action — continue the
    /// latest board, or start a new game when nothing's in progress — which keeps the
    /// baked-in「▶ PRESS START ◀」honest. The cards below make the same actions
    /// explicit, so the art is a shortcut, not an invisible fork.
    var artButton: some View {
        Button {
            if let latest = snapshots.first {
                onContinue(latest.config)
            } else {
                onNewGame()
            }
        } label: {
            Image("TitleScreen", bundle: .module)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 5)
        }
        .buttonStyle(.plain)
        // iOS keeps Return as a shortcut (no KeyCatcher on this screen); on
        // macOS the catcher runs the same action itself — see
        // activateFocusedItem — because a shortcut-activated button leaves
        // SwiftUI focus fighting the board's first-responder claim.
        #if os(iOS)
        .keyboardShortcut(.defaultAction)
        #endif
        .accessibilityLabel(Text(snapshots.isEmpty ? "Start" : "Continue", bundle: .module))
        .accessibilityIdentifier("title.start")
    }
}
