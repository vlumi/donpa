import DonpaCore
import SwiftUI

/// The in-game action buttons, in their fixed far-edge → toggle order.
enum GameAction: Hashable { case home, retry, pause, minimap }

/// The in-game chrome for `GameContent`: the top metrics strip, the board + its
/// control strip (actions + flag toggle), and the pause overlay.
extension GameContent {
    // MARK: Board + control strip

    var leftHanded: Bool { settings.handedness == .left }

    /// The strip never overlaps the board, and stays visible after the game
    /// ends so the actions remain reachable.
    var boardArea: some View {
        GeometryReader { geo in
            // The strip goes where the board leaves the most room.
            let windowAspect = geo.size.width / max(geo.size.height, 1)
            let boardAspect = CGFloat(viewModel.boardWidth) / CGFloat(max(viewModel.boardHeight, 1))
            let sideStrip = windowAspect > boardAspect

            if sideStrip {
                HStack(spacing: 0) {
                    if leftHanded { sideControlStrip.frame(width: 108) }
                    board
                    if !leftHanded { sideControlStrip.frame(width: 108) }
                }
            } else {
                VStack(spacing: 0) {
                    board
                    bottomControlStrip.frame(height: 84)
                }
            }
        }
    }

    /// Always present (stable control set); disabled once the board is finished.
    var toggleControl: some View {
        modeToggle
            .disabled(!gameInProgress)
            .opacity(gameInProgress ? 1 : 0.55)
    }

    /// Flag toggle pinned to the handed end (under the thumb).
    var bottomControlStrip: some View {
        HStack(spacing: 8) {
            if leftHanded { toggleControl; Spacer(minLength: 8) }
            actionButtons(vertical: false)
            if !leftHanded { Spacer(minLength: 8); toggleControl }
        }
        .padding(.horizontal, 12)
    }

    /// Toggle at the bottom, for thumb reach.
    var sideControlStrip: some View {
        VStack(spacing: 8) {
            actionButtons(vertical: true)
            Spacer(minLength: 8)
            toggleControl
        }
        .padding(.vertical, 12)
    }

    var board: some View {
        BoardView(
            scene: scene, palette: palette, inputMode: viewModel.inputMode,
            // Custom reveal/flag cursor only during a live, non-paused game with
            // nothing modal above it; the normal arrow elsewhere.
            boardCursorActive: gameInProgress && !navigator.showingTitle
                && !viewModel.isPaused && !navigator.isModalPresented,
            // Keyboard ownership INCLUDES paused (Esc must reach the scene to
            // resume) but never the title or a modal — a sheet's text field
            // is never robbed, and the KeyCatcher surfaces never fight.
            keyboardOwner: gameInProgress && !navigator.showingTitle
                && !navigator.isModalPresented,
            minimap: MinimapPrefs(
                show: settings.showMinimap,
                onRight: settings.handedness == .right,
                scale: settings.minimapScale),
            useQuestionMarks: settings.questionMarks
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The focused-cell cursor IS the per-cell VoiceOver interface — see
        // BoardCellA11y (CellVoiceOver.swift).
        .modifier(BoardCellA11y(viewModel: viewModel, scene: scene, summary: boardSummary))
        .overlay { mangaPanel }
        .overlay { pauseOverlay }
        .overlay { processingOverlay }
        .overlay(alignment: .top) { guessToastOverlay }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isPaused)
        .animation(.easeInOut(duration: 0.15), value: showProcessing)
        .clipped()  // keep the dimmed backdrop within the board's bounds
    }

    @ViewBuilder var processingOverlay: some View {
        if showProcessing {
            ZStack {
                Rectangle()
                    .fill(palette.pageBackground.opacity(0.4))
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Working…", bundle: .module)
                        .font(.headline)
                        .foregroundStyle(palette.counter)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            .transition(.opacity)
            .allowsHitTesting(false)  // input is gated in the model
        }
    }

    /// Blurs rather than blacks out, so it reads "paused", not "blank".
    @ViewBuilder var pauseOverlay: some View {
        if viewModel.isPaused {
            GeometryReader { geo in
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(palette.pageBackground.opacity(0.5))
                    // Sized like the result panel, so the two match.
                    let shorter = min(geo.size.width, geo.size.height)
                    let panelW = min(max(shorter * 0.82, 220), 900)
                    VStack(spacing: 12) {
                        Image("PanelPause", bundle: .module)
                            .resizable()
                            .interpolation(.high)
                            .antialiased(true)
                            .scaledToFit()
                            .frame(
                                maxWidth: min(panelW, geo.size.width - 24),
                                maxHeight: geo.size.height - 100
                            )
                            .shadow(color: .black.opacity(0.35), radius: 14, y: 5)
                        // The drill command; a11y keeps the plain "Paused" below.
                        Text("At ease!", bundle: .module)
                            .font(.title2.bold())
                        Text("Tap to resume", bundle: .module)
                            .font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                        #if os(macOS)
                        // Esc pauses, so the keyboard is in hand — teach its keys.
                        Text(
                            "Arrows move · Return digs · F flags — ⌘/ for all shortcuts",
                            bundle: .module
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        #endif
                        // Its own Button consumes the tap so it doesn't also resume.
                        Button {
                            settings.sound.toggle()
                        } label: {
                            Label {
                                Text(settings.sound ? "Sound on" : "Sound off", bundle: .module)
                            } icon: {
                                Image(
                                    systemName: settings.sound
                                        ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            }
                            .font(.callout)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("game.paused.sound")
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { viewModel.resume() }
            .transition(.opacity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Paused", bundle: .module))
            .accessibilityHint(Text("Tap to resume", bundle: .module))
            .accessibilityIdentifier("game.paused")
        }
    }

    /// Far-edge → toggle: Home furthest (hardest to mis-tap), Pause nearest
    /// the thumb; mirrored for a left-handed strip.
    @ViewBuilder
    func actionButtons(vertical: Bool) -> some View {
        let layout =
            vertical
            ? AnyLayout(VStackLayout(spacing: 16)) : AnyLayout(HStackLayout(spacing: 16))
        let reverse = !vertical && leftHanded
        let ordered = reverse ? Array(actionOrder.reversed()) : actionOrder
        layout {
            ForEach(ordered, id: \.self) { action in
                actionView(action)
            }
        }
    }

    /// Fixed sequence — the row never reflows; buttons disable instead.
    private var actionOrder: [GameAction] { [.home, .retry, .pause, .minimap] }

    @ViewBuilder
    private func actionView(_ action: GameAction) -> some View {
        switch action {
        case .home:
            actionButton(.home, help: "Barracks") { navigator.homeRequested &+= 1 }
                .accessibilityIdentifier("game.home")
        case .retry:
            actionButton(.retry, help: "Retry", tint: newGameTint) { viewModel.newGame() }
                .accessibilityIdentifier("game.retry")
        case .pause:
            let paused = viewModel.isPaused
            let live = viewModel.status.isPlaying
            actionButton(
                paused ? .play : .pause, help: paused ? "Resume" : "Pause"
            ) {
                if paused { viewModel.resume() } else { viewModel.pause() }
            }
            .disabled(!live && !paused)
            .opacity(live || paused ? 1 : 0.4)
            .accessibilityIdentifier("game.pause")
        case .minimap:
            mapButton(
                .minimap, help: "Overview map", id: "game.minimap",
                tint: settings.showMinimap ? palette.counter : .secondary
            ) { settings.showMinimap.toggle() }
        }
    }

    /// A toolbar button for a map control: disabled + dimmed when the board fits.
    @ViewBuilder
    private func mapButton(
        _ symbol: MangaIcon.Symbol, help: LocalizedStringKey, id: String,
        tint: Color = .secondary, action: @escaping () -> Void
    ) -> some View {
        let available = viewModel.boardExceedsViewport
        actionButton(symbol, help: help, tint: tint, action: action)
            .disabled(!available)
            .opacity(available ? 1 : 0.4)
            .accessibilityIdentifier(id)
    }

    func actionButton(
        _ symbol: MangaIcon.Symbol, help: LocalizedStringKey, tint: Color = .secondary,
        action: @escaping () -> Void
    ) -> some View {
        let label = Text(help, bundle: .module)
        return Button(action: action) {
            MangaIcon(symbol: symbol, size: 38, tint: tint)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    var statusDescription: String {
        switch viewModel.status {
        case .won: return String(localized: "Won", bundle: .module)
        case .lost: return String(localized: "Lost", bundle: .module)
        case .playing: return String(localized: "In progress", bundle: .module)
        case .notStarted: return String(localized: "Ready", bundle: .module)
        }
    }

    var boardSummary: String {
        let label = viewModel.config.label
        let width = viewModel.boardWidth
        let height = viewModel.boardHeight
        let mines = viewModel.flagsRemaining
        let status = statusDescription
        return String(
            localized: "\(label), \(width) by \(height), \(mines) mines remaining, \(status)",
            bundle: .module)
    }

    var newGameTint: Color {
        switch viewModel.status {
        case .won: return .green
        case .lost: return .red
        case .notStarted, .playing: return .secondary
        }
    }

    // From the palette, so the toggle and the SpriteKit glow never drift.
    var digColor: Color { palette.digColor }
    var flagColor: Color { palette.flagColor }

    func mangaIconButton(
        _ symbol: MangaIcon.Symbol, size: CGFloat, help: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        let label = Text(help, bundle: .module)
        return Button(action: action) {
            MangaIcon(symbol: symbol, size: size, tint: .secondary)
                .frame(width: 44, height: 44)  // Apple's min touch target
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    /// Looks segmented, but the WHOLE pill is one button that flips the mode —
    /// no need to aim at a half.
    var modeToggle: some View {
        let flagging = viewModel.inputMode == .flag
        return Button(action: { viewModel.inputMode.toggle() }) {
            HStack(spacing: 0) {
                modeSegment(.reveal, active: !flagging, fill: digColor)
                modeSegment(.flag, active: flagging, fill: flagColor)
            }
            .background(Capsule().fill(palette.statusBar.opacity(0.6)))
            .overlay(Capsule().stroke(.primary.opacity(0.15), lineWidth: 1))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
        .help(
            flagging
                ? Text("Flag mode — tap flags (Space)", bundle: .module)
                : Text("Dig mode — tap reveals (Space)", bundle: .module)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Input mode", bundle: .module))
        .accessibilityValue(
            flagging ? Text("Flag", bundle: .module) : Text("Dig", bundle: .module)
        )
        .accessibilityHint(Text("Toggles between revealing and flagging", bundle: .module))
    }

    /// Pure visual — the pill is the button. The screentone matches the
    /// board's unopened-tile texture for that mode.
    private func modeSegment(_ symbol: MangaIcon.Symbol, active: Bool, fill: Color) -> some View {
        MangaIcon(symbol: symbol, size: 34, tint: active ? .white : .secondary)
            .frame(width: 50, height: 60)
            .background {
                ZStack {
                    if active { fill }
                    ScreentonePattern(
                        dots: symbol == .reveal,
                        color: active ? .white.opacity(0.35) : .primary.opacity(0.18))
                }
            }
    }
}
