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
    let onScores: () -> Void
    /// Open the Mess hall — the social screen (share card, rivals, squads).
    let onMessHall: () -> Void
    let onSettings: () -> Void
    let onAbout: () -> Void
    let onHowTo: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// Whether the full in-progress list sheet is presented.
    @State var showAll = false

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
                        id: "title.sound", action: { settings.sound.toggle() }
                    ) {
                        Image(
                            systemName: settings.sound
                                ? "speaker.wave.2.fill" : "speaker.slash.fill"
                        )
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    }
                    roundButton(label: "How to play", id: "title.howto", action: onHowTo) {
                        Image(systemName: "questionmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    roundButton(label: "Settings", id: "title.settings", action: onSettings) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    roundButton(label: "About", id: "title.about", action: onAbout) {
                        Image(systemName: "info")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(16)
            }
            .sheet(isPresented: $showAll) { inProgressSheet }
        }
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
                continueCard(latest: latest)
            }
            newGameButton
            recordButton
            messHallButton
        }
    }

    // MARK: Masthead art

    /// The manga splash. Tappable as a shortcut for the PRIMARY action — continue the
    /// latest board, or start a new game when nothing's in progress — which keeps the
    /// baked-in「▶ PRESS START ◀」honest. The cards below make the same actions
    /// explicit, so the art is a shortcut, not an invisible fork.
    private var artButton: some View {
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
        .keyboardShortcut(.defaultAction)
        .accessibilityLabel(Text(snapshots.isEmpty ? "Start" : "Continue", bundle: .module))
        .accessibilityIdentifier("title.start")
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
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button(action: action) {
            icon()
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.55), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
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
