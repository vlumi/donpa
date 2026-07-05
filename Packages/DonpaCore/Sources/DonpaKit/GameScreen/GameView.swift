import DonpaCore
import SpriteKit
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// The game surface. Lives below `GameView`'s `.preferredColorScheme`, so its
/// `@Environment(\.colorScheme)` is the effective appearance the chrome and the
/// SKScene both use.
struct GameContent: View {
    @ObservedObject var viewModel: GameViewModel
    @ObservedObject var scoreboard: Scoreboard
    @ObservedObject var settings: Settings
    @ObservedObject var navigator: Navigator
    @ObservedObject var friends: FriendsStore
    let scene: BoardScene

    // Non-private (like restartPop/showProcessing): used by the GameContent+Result
    // extension file.
    @State var panel: MangaPanelView.Kind?
    @State var panelTask: Task<Void, Never>?
    /// Coalesces the per-move autosave: snapshotting a huge board is expensive, so
    /// saving on every reveal stalls the main thread. Save once activity settles;
    /// the periodic/pause/Home/quit saves are the durability backstops.
    @State private var autosaveTask: Task<Void, Never>?
    @State var restartPop = false
    /// Whether to SHOW the processing overlay — debounced off `viewModel.isComputing`
    /// so a fast compute never flashes it. (The input gate uses `isComputing`
    /// directly; only the visual waits.) Driven by `driveProcessingOverlay`.
    @State var showProcessing = false
    @State private var processingTask: Task<Void, Never>?
    @State private var processingShownAt: Date?
    @State private var windowSize: CGSize = .zero
    /// True when WE paused to show the scoreboard — used to auto-resume on dismiss,
    /// but only if the player hadn't already paused it themselves.
    @State private var pausedForScores = false
    /// Atomic, crash-safe store for the in-progress game. Ephemeral under the
    /// UI-test launch arg so tests never touch the real save.
    @State private var saveStore: SaveStore
    /// Writes the save off the main thread so it never stalls input. The snapshot is
    /// still BUILT on the main actor; only the encode + atomic write is handed here.
    @State private var saveWriter: BackgroundSaveWriter
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    /// Periodic crash-protection save: pure pan/zoom doesn't bump `revision`, so an
    /// unflushed reframe could be lost to a crash. Flushes ~once a minute while live
    /// (deliberate exits save immediately; this is the safety net).
    private let autosaveHeartbeat =
        Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    #if os(macOS)
    /// Fires just before the app quits — the macOS save-on-exit hook (see body).
    private var appWillTerminate: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
    }
    #endif

    init(
        viewModel: GameViewModel, scoreboard: Scoreboard, settings: Settings,
        navigator: Navigator, friends: FriendsStore, scene: BoardScene
    ) {
        self.viewModel = viewModel
        self.scoreboard = scoreboard
        self.settings = settings
        self.navigator = navigator
        self.friends = friends
        self.scene = scene
        // One store backs both the synchronous reads and the background writer.
        let store =
            SaveStore.isUITestCleanLaunch ? SaveStore.ephemeral() : SaveStore.appSupport()
        _saveStore = State(initialValue: store)
        _saveWriter = State(initialValue: BackgroundSaveWriter(store: store))
    }

    /// One resolved scheme for chrome and scene. `colorScheme` is the iOS fallback,
    /// but reading it also re-runs `body` when the OS appearance flips on System.
    private var scheme: ColorScheme {
        settings.appearance.resolvedScheme(systemFallback: colorScheme)
    }
    var palette: Palette { .resolved(for: scheme) }

    /// A live game (not yet won/lost) — the only time the board takes input.
    var gameInProgress: Bool {
        viewModel.status == .notStarted || viewModel.status == .playing
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            boardArea
        }
        .background(palette.pageBackground)
        // Track the window size so sheets can size to it.
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { windowSize = geo.size }
                    .onChangeCompat(of: geo.size) { windowSize = $0 }
            }
        )
        .onAppear { onLaunch() }
        .onChangeCompat(of: viewModel.lastResult?.id) { _ in handleResult() }
        // Any new game (New Game / Retry / ⌘R) clears a lingering panel.
        .onChangeCompat(of: viewModel.gameID) { _ in dismissPanel() }
        // Debounced save (see `autosaveSoon`); a per-move snapshot would stall a
        // huge board. Durability covered by the periodic/pause/Home/quit saves.
        .onChangeCompat(of: viewModel.revision) { _ in autosaveSoon() }
        // Leaving the foreground auto-pauses and saves inline (the process may
        // suspend/exit before a background task could run).
        .onChangeCompat(of: scenePhase) { phase in
            if phase != .active {
                viewModel.pause()
                autosaveBlocking()
            } else {
                // Pull latest scores from iCloud, so a change on another device
                // lands even if the live notification was missed.
                scoreboard.refreshFromCloud()
            }
        }
        // Pause is a natural "stepping away" save (and doesn't bump `revision`).
        .onChangeCompat(of: viewModel.isPaused) { paused in
            if paused { autosave() }
        }
        .onChangeCompat(of: viewModel.isComputing) { driveProcessingOverlay(computing: $0) }
        .onReceive(autosaveHeartbeat) { _ in
            if scenePhase == .active { autosave() }
        }
        // ⌘Q doesn't reliably deliver a `scenePhase` change before exit, so the
        // background-save above can miss it; `willTerminate` fires synchronously in
        // time. (iOS uses the `scenePhase` background transition instead.)
        #if os(macOS)
        .onReceive(appWillTerminate) { _ in
            viewModel.pause()
            autosaveBlocking()  // exiting; the write must finish inline
        }
        #endif
        .sheet(isPresented: $navigator.showingScores) {
            // From the title (browsing) there's no current board → no "you are here"
            // marker. In-game, mark the row for the config being played.
            ScoreboardView(
                scoreboard: scoreboard, settings: settings, available: windowSize,
                currentConfig: navigator.showingTitle ? nil : viewModel.config,
                onPlay: { navigator.playConfigRequested = $0 },
                // A rival URL scanned in the Share sheet's Scan tab: classify it and
                // present the receive prompt at the root. Deferred a tick — the
                // scoreboard is dismissing, and two sheet swaps in one runloop race.
                onReceiveURL: { url in
                    let incoming = GameView.classify(url, existing: friends.friends)
                    Task { @MainActor in navigator.incomingShare = incoming }
                },
                onFriends: {
                    navigator.showingScores = false
                    Task { @MainActor in navigator.showingFriends = true }
                },
                friends: friends)
        }
        // Opening the scoreboard pauses a live game (flushing career activity and
        // stopping the clock); auto-resume on dismiss only if WE paused.
        .onChangeCompat(of: navigator.showingScores) { showing in
            if showing {
                if viewModel.game.status == .playing && !viewModel.isPaused {
                    pausedForScores = true
                    viewModel.pause()
                }
            } else if pausedForScores {
                pausedForScores = false
                viewModel.resume()
            }
        }
        .sheet(isPresented: $navigator.showingSettings) {
            SettingsView(settings: settings, scoreboard: scoreboard)
        }
        .sheet(isPresented: $navigator.showingAbout) {
            AboutView()
        }
        .onChangeCompat(of: navigator.startRequested) { _ in handleStartRequest() }
        .onChangeCompat(of: navigator.playConfigRequested) { config in
            if let config { playFromScoreboard(config) }
        }
        .onChangeCompat(of: navigator.homeRequested) { _ in goHome() }
        .onChangeCompat(of: navigator.zoomInRequested) { _ in scene.zoom(by: 1.25) }
        .onChangeCompat(of: navigator.zoomOutRequested) { _ in scene.zoom(by: 0.8) }
        .onChangeCompat(of: navigator.toggleMinimapRequested) { _ in scene.toggleMinimapSize() }
    }

    // MARK: Save / restore lifecycle

    /// On launch: resume a saved in-progress game straight into the board (skipping
    /// the title), else stay on the title with the board primed to the persisted
    /// config so an immediate New Game matches the last selection.
    private func onLaunch() {
        // Persist a minimap resize back to Settings (survives new game / restart /
        // save-restore). The scene drives the gesture; Settings is the store.
        scene.onMinimapScaleChange = { settings.minimapScale = Double($0) }
        // Fold each live activity-flush delta (tiles/flags/time) into the lifetime
        // totals WITHOUT counting a game played — the outcome is recorded at end.
        // Wired before any newGame below so the first flush is caught.
        viewModel.onActivityFlush = { [weak viewModel] tiles, flags, centiseconds in
            // Weak: the closure lives ON viewModel — a strong capture is a self-cycle
            // (harmless for these app-lifetime objects today, a leak in any future
            // scene-per-window world).
            guard let viewModel else { return }
            scoreboard.recordActivity(
                for: viewModel.config, tilesOpened: tiles, flagsPlaced: flags,
                playtimeCentiseconds: centiseconds)
        }
        if let scenario = PerfScenario.current {
            startPerfScenario(scenario)
        } else if let snapshot = saveStore.latest() {
            // Auto-resume the most-recently-played in-progress game (per-config saves).
            viewModel.restore(from: snapshot)
            navigator.showingTitle = false
        } else if viewModel.config != settings.currentConfig {
            viewModel.newGame(config: settings.currentConfig)
        }
    }

    /// Jump straight into a profiling scenario (see `PerfScenario`): start the heavy
    /// board, fill the screen, and open a region — off the title — so the harness
    /// measures the same state the manual repro hit (render cost scales with the
    /// visible-node count, hence a maximized window).
    private func startPerfScenario(_ scenario: PerfScenario) {
        switch scenario {
        case .xxxlOpened:
            // Fixed seed → identical mine layout every run, so before/after profiles
            // compare like with like (the revealed region is then near-identical too).
            viewModel.newGame(config: .grid(.xxxl, .normal, .flat), seed: 0xDEAD_BEEF)
            navigator.showingTitle = false
            #if os(macOS)
            // Maximize so the viewport shows a full screen of cells (the heavy case).
            DispatchQueue.main.async {
                if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }),
                    let screen = window.screen ?? NSScreen.main
                {
                    window.setFrame(screen.visibleFrame, display: true)
                }
            }
            #endif
            // Open a region once mines finish arming. `newGame` arms the board off
            // the main thread (`isComputing` true), and `reveal` is gated on
            // `canTakeInput` — so revealing immediately here would be DROPPED and
            // nothing would open. Await the arming, then reveal: the first click is
            // first-click-safe and floods a region (the heavy render + autosave-scan
            // state the perf work targets). Exact tiles vary by RNG; the load is
            // stable. A second reveal nearby widens the opened area.
            Task {
                await viewModel.awaitPendingWork()
                let w = viewModel.boardWidth, h = viewModel.boardHeight
                viewModel.reveal(Coord(w / 2, h / 2))
                await viewModel.awaitPendingWork()
                viewModel.reveal(Coord(w / 2 + 7, h / 2 + 7))
            }
        }
    }

    /// "Press start": if there are in-progress boards, show the Continue list (pick
    /// one to resume, or start fresh); with none, open the New Game popup directly.
    /// The title stays up behind either — the actual leave-title happens on the pick.
    /// The single place the resume decision lives, since `saveStore` is owned here.
    private func handleStartRequest() {
        if saveStore.latest() != nil {
            navigator.showingResumeList = true
        } else {
            navigator.showingTitle = false
            navigator.showingNewGame = true
        }
    }

    /// Start a fresh game on the config the player tapped in the scoreboard, then
    /// dismiss the sheet and leave the title. Clear the pause-for-scores flag so the
    /// dismiss handler doesn't resume the OLD (now replaced) game. Behaves like the
    /// New Game popup's Start — no confirm; the fresh game replaces the current one.
    private func playFromScoreboard(_ config: GameConfig) {
        pausedForScores = false
        navigator.playConfigRequested = nil
        navigator.showingScores = false
        settings.adopt(config)  // remember it as the current selection (New Game / relaunch)
        viewModel.newGame(config: config)
        navigator.showingTitle = false
    }

    /// Persist the live game, or clear the save once it's no longer in progress.
    ///
    /// Building the snapshot scans the whole board to derive the revealed/flagged
    /// coord sets — heavy on a 1M-cell board, and it used to run on the main actor,
    /// stalling input (a beachball on a weak CPU mid-reveal). So capture the cheap
    /// Sendable inputs here, then build the snapshot AND encode/write off the main
    /// thread via `saveWriter`. Falls back to clearing the save once not in progress.
    private func autosave() {
        autosaveTask?.cancel()  // an explicit save subsumes any pending debounce
        if let inputs = viewModel.snapshotInputs() {
            Task.detached(priority: .utility) {
                guard let snapshot = GameSnapshot(inputs: inputs) else { return }
                await saveWriter.write(snapshot)
            }
        } else {
            // Not in progress (won/lost/not started) → discard THIS config's save.
            let config = viewModel.config
            Task { await saveWriter.clear(config: config) }
        }
    }

    /// Debounce the processing overlay so it never flashes: wait a grace period and
    /// show only if STILL computing; once shown, keep it up a minimum duration. Both
    /// together are hardware-independent (a fixed threshold alone can't win).
    private func driveProcessingOverlay(computing: Bool) {
        let grace: TimeInterval = 0.12  // don't show for quick work
        let minVisible: TimeInterval = 0.3  // once shown, don't blip
        processingTask?.cancel()
        processingTask = Task {
            if computing {
                try? await Task.sleep(nanoseconds: UInt64(grace * 1e9))
                guard !Task.isCancelled, viewModel.isComputing, !showProcessing else { return }
                showProcessing = true
                processingShownAt = Date()
            } else if showProcessing {
                let elapsed = processingShownAt.map { Date().timeIntervalSince($0) } ?? minVisible
                let remaining = minVisible - elapsed
                if remaining > 0 { try? await Task.sleep(nanoseconds: UInt64(remaining * 1e9)) }
                guard !Task.isCancelled else { return }
                showProcessing = false
            }
        }
    }

    /// A SYNCHRONOUS save for app-exit paths (backgrounding, ⌘Q): the process may
    /// terminate the instant the handler returns, so the write must finish inline.
    private func autosaveBlocking() {
        autosaveTask?.cancel()
        if let snapshot = viewModel.snapshot() {
            saveStore.save(snapshot)
        } else {
            saveStore.clear(config: viewModel.config)
        }
    }

    /// Schedule a save shortly after the last move, coalescing a burst of reveals
    /// into one write (a per-move snapshot would stall a huge board). The
    /// periodic/pause/Home/quit saves remain the durability backstops.
    private func autosaveSoon() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            autosave()
        }
    }

    // Result feedback (manga result screen + restart pop + haptics) lives in
    // GameContent+Result.swift.

    /// Return home WITHOUT ending the game: pause and save, so "press start" can
    /// resume where it left off. Discarding is an explicit New Game instead.
    func goHome() {
        viewModel.pause()
        autosave()
        navigator.showingTitle = true
    }
}

// ScoreboardView and SettingsView live in SheetViews.swift.
