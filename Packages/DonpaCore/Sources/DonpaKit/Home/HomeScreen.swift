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
    let onSettings: () -> Void
    let onAbout: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// Whether the in-progress list (beyond the latest) is expanded.
    @State private var showAll = false

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
                    portraitLayout
                }
            }
            // Secondary utilities in the screen's top-right corner, as before.
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 8) {
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
        }
    }

    // MARK: Layouts

    /// The menu column's width beside the art (landscape) / its cap below it
    /// (portrait, where the art shares the same cap so they read as one column).
    private static let menuWidth: CGFloat = 340
    private static let portraitColumnMaxWidth: CGFloat = 480

    /// Portrait (phone, or a tall window): one column — full-width art over the
    /// menu, centered when it fits, scrolling when it doesn't (e.g. the expanded
    /// in-progress list on a short phone).
    private var portraitLayout: some View {
        ViewThatFits(in: .vertical) {
            portraitColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ScrollView(showsIndicators: false) {
                portraitColumn
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var portraitColumn: some View {
        VStack(spacing: 16) {
            artButton
                .frame(maxWidth: Self.portraitColumnMaxWidth)
            menu
                .frame(maxWidth: Self.portraitColumnMaxWidth)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
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
    /// New Game, Service Record.
    private var menu: some View {
        VStack(spacing: 12) {
            if let latest = snapshots.first {
                continueCard(latest: latest)
            }
            newGameButton
            recordButton
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

    // MARK: Continue

    /// The latest in-progress board as the leading card, plus — when there are more —
    /// an expander revealing the rest inline (newest first).
    private func continueCard(latest: SaveStore.SaveSummary) -> some View {
        VStack(spacing: 0) {
            Button {
                onContinue(latest.config)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text("Continue", bundle: .module)
                    } icon: {
                        Image(systemName: "arrow.uturn.forward.circle.fill")
                    }
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                    savedGameRow(latest)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.continue")

            if snapshots.count > 1 {
                Divider()
                expander
                if showAll {
                    ForEach(snapshots.dropFirst(), id: \.config) { snapshot in
                        Divider()
                        Button {
                            onContinue(snapshot.config)
                        } label: {
                            savedGameRow(snapshot)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.accentColor.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.accentColor.opacity(0.55), lineWidth: 1.5))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// The "More in progress (N)" toggle revealing the non-latest saves. The count
    /// is what the accordion ADDS (the latest is already on the card above), so two
    /// saves read as "More in progress (1)".
    private var expander: some View {
        Button {
            withAnimation(.snappy) { showAll.toggle() }
        } label: {
            HStack {
                Text("More in progress", bundle: .module)
                Text(verbatim: "(\(snapshots.count - 1))")
                Spacer()
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(showAll ? 180 : 0))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.inprogress")
    }

    /// One in-progress board: glyph, family + config (with cleared %), and — trailing —
    /// the elapsed clock over a relative "last played" age.
    private func savedGameRow(_ snapshot: SaveStore.SaveSummary) -> some View {
        HStack(spacing: 12) {
            BoardGlyph(kind: .family(snapshot.config.family), size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: snapshot.config.family.label)
                    .font(.headline)
                Text(verbatim: "\(snapshot.config.label) · \(snapshot.progressPercent)%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: Self.clock(snapshot.elapsedCentiseconds))
                    .font(.subheadline.monospacedDigit())
                Text(snapshot.updatedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
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
