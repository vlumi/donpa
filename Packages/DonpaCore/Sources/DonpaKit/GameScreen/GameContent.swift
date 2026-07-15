import DonpaCore
import SpriteKit
import StoreKit
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
    @ObservedObject var achievements: AchievementStore
    @ObservedObject var gameCenter: GameCenterReporter
    @ObservedObject var dailyStore: DailyStore
    let scene: BoardScene
    /// `-donpa.gates.fresh` baseline: only wins earned this session count.
    var winsBaseline: [String: Int] = [:]

    var gates: UnlockGates {
        UnlockGates(
            records: scoreboard.displayRecords, winsBaseline: winsBaseline,
            bypassAll: settings.unlockAll)
    }

    @State var panel: MangaPanelView.Kind?
    @State var panelTask: Task<Void, Never>?
    @State var panelUnlocks: [String] = []
    @State var panelFeats: [String] = []
    /// The first-decoration Game Center ask — shown only after the result
    /// panel dismisses, never over the celebration.
    @State var pendingGCAsk = false
    @State var showGCAsk = false
    @State var pendingReviewAsk = false
    @State var panelPace: Double?
    @State var panelPaceIsRecord = false
    @State var guessToast: ForcedGuessEvent?
    @State var guessToastTask: Task<Void, Never>?
    @State private var autosaveTask: Task<Void, Never>?
    @State var restartPop = false
    @State var showProcessing = false
    @State private var processingTask: Task<Void, Never>?
    @State private var processingShownAt: Date?
    @State var windowSize: CGSize = .zero
    /// Auto-resume on dismiss only if WE paused — not the player.
    @State private var pausedForScores = false
    @State private var pausedForNewGame = false
    @State private var saveStore: SaveStore
    @State private var saveWriter: BackgroundSaveWriter
    @Environment(\.requestReview) var requestReview
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    /// Crash-protection net: pure pan/zoom doesn't bump `revision`, so the
    /// debounced autosave alone could lose a reframe.
    private let autosaveHeartbeat =
        Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    #if os(macOS)
    private var appWillTerminate: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
    }
    #endif

    init(
        viewModel: GameViewModel, scoreboard: Scoreboard, settings: Settings,
        navigator: Navigator, friends: FriendsStore, achievements: AchievementStore,
        gameCenter: GameCenterReporter, dailyStore: DailyStore,
        scene: BoardScene, winsBaseline: [String: Int] = [:], saveStore: SaveStore
    ) {
        self.viewModel = viewModel
        self.scoreboard = scoreboard
        self.settings = settings
        self.navigator = navigator
        self.friends = friends
        self.achievements = achievements
        self.gameCenter = gameCenter
        self.dailyStore = dailyStore
        self.scene = scene
        self.winsBaseline = winsBaseline
        // Shared with GameViewRoot so the New Game popup's resume cues read the
        // same files this view writes.
        _saveStore = State(initialValue: saveStore)
        _saveWriter = State(initialValue: BackgroundSaveWriter(store: saveStore))
    }

    /// One resolved scheme for chrome and scene. `colorScheme` is the iOS fallback,
    /// but reading it also re-runs `body` when the OS appearance flips on System.
    private var scheme: ColorScheme {
        settings.appearance.resolvedScheme(systemFallback: colorScheme)
    }
    var palette: Palette { .resolved(for: scheme) }

    var gameInProgress: Bool { viewModel.status.isLive }

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
        .onChangeCompat(of: viewModel.lastForcedGuess) { handleGuessEvent($0) }
        .onChangeCompat(of: viewModel.gameID) { _ in
            dismissPanel()
            // Every daily attempt (first or retry) opens in review.
            navigator.dailyReviewActive = navigator.activeDaily != nil
        }
        .onChangeCompat(of: viewModel.revision) { _ in autosaveSoon() }
        // Save INLINE when leaving the foreground — the process may suspend
        // before a background task could run.
        .onChangeCompat(of: scenePhase) { phase in
            if phase != .active {
                viewModel.pause()
                autosaveBlocking()
            } else {
                // A change on another device lands even if its notification was missed.
                scoreboard.refreshFromCloud()
            }
        }
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
        .sheet(isPresented: $navigator.showingScores) { scoreboardSheet }
        // Browsing scores shouldn't cost clock time; resume only OUR pause.
        .onChangeCompat(of: navigator.showingScores) { showing in
            if showing {
                if viewModel.playState == .playing {
                    pausedForScores = true
                    viewModel.pause()
                }
            } else if pausedForScores {
                pausedForScores = false
                viewModel.resume()
            }
        }
        // Same for the New Game popup. Starting from the popup is safe:
        // newGame/restore leave isPaused false, so this resume() no-ops.
        .onChangeCompat(of: navigator.showingNewGame) { showing in
            if showing {
                if viewModel.playState == .playing {
                    pausedForNewGame = true
                    viewModel.pause()
                }
            } else if pausedForNewGame {
                pausedForNewGame = false
                viewModel.resume()
            }
        }
        .sheet(isPresented: $navigator.showingSettings) {
            SettingsView(settings: settings, scoreboard: scoreboard)
        }
        .sheet(isPresented: $navigator.showingAbout) {
            // Two sheet swaps in one runloop turn race; defer the second a tick.
            AboutView(onHowTo: {
                navigator.showingAbout = false
                navigator.afterDismiss { navigator.showingHowTo = true }
            })
        }
        .sheet(isPresented: $navigator.showingHowTo) {
            HowToPlayView()
        }
        .sheet(isPresented: $navigator.showingShortcuts) {
            KeyboardShortcutsView()
        }
        .sheet(isPresented: $navigator.showingDailyCalendar) {
            DailyCalendarView(dailyStore: dailyStore) { board in
                navigator.showingDailyCalendar = false
                startDailyBoard(board)
            }
        }
        .onChangeCompat(of: navigator.playConfigRequested) { config in
            if let config { playFromScoreboard(config) }
        }
        .onChangeCompat(of: navigator.homeRequested) { _ in goHome() }
        .onChangeCompat(of: navigator.zoomInRequested) { _ in scene.zoom(by: 1.25) }
        .onChangeCompat(of: navigator.zoomOutRequested) { _ in scene.zoom(by: 0.8) }
        .onChangeCompat(of: navigator.toggleMinimapRequested) { _ in scene.toggleMinimapSize() }
        .onChangeCompat(of: navigator.restartRequested) { _ in restartGame() }
        .onChangeCompat(of: settings.sound) { scene.soundPlayer?.isEnabled = $0 }
        .onChangeCompat(of: settings.haptics) { scene.hapticPlayer?.isEnabled = $0 }
    }

    // MARK: Save / restore lifecycle

    private func onLaunch() {
        scene.onMinimapScaleChange = { settings.minimapScale = Double($0) }
        scene.soundPlayer?.isEnabled = settings.sound
        scene.hapticPlayer?.isEnabled = settings.haptics
        // The flood sting means "hit a 0": a chord that merely clears numbers ticks.
        viewModel.onReveal = { [weak scene] opened, flooded in
            scene?.soundPlayer?.play(flooded ? .flood : .reveal)
            scene?.hapticPlayer?.reveal(openedCells: opened)
        }
        // Activity deltas fold into lifetime totals WITHOUT counting a game
        // played; wired before any newGame so the first flush is caught.
        viewModel.onActivityFlush = { [weak viewModel] tiles, flags, centiseconds in
            // The closure lives ON viewModel — a strong capture is a self-cycle.
            guard let viewModel else { return }
            scoreboard.recordActivity(
                for: viewModel.config, tilesOpened: tiles, flagsPlaced: flags,
                playtimeCentiseconds: centiseconds)
        }
        // The config rides along because the analysis is async.
        viewModel.onForcedGuess = { config, survival, survived in
            scoreboard.recordForcedGuess(for: config, survival: survival, survived: survived)
        }
        if let scenario = PerfScenario.current {
            startPerfScenario(scenario)
        } else if viewModel.config != settings.currentConfig {
            // `prime`, not `newGame`: the swap is OUR placeholder — autosave must
            // not read it as the player abandoning that config's saved game.
            viewModel.prime(config: settings.currentConfig)
        }
    }

    /// Profiling harness (see `PerfScenario`): reproduce the heavy state —
    /// maximized window, opened region — identically run to run.
    private func startPerfScenario(_ scenario: PerfScenario) {
        switch scenario {
        case .xxxlOpened:
            // Fixed seed → before/after profiles compare like with like.
            viewModel.newGame(config: .grid(.xxxl, .normal, .flat), seed: 0xDEAD_BEEF)
            navigator.showingTitle = false
            #if os(macOS)
            DispatchQueue.main.async {
                if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }),
                    let screen = window.screen ?? NSScreen.main
                {
                    window.setFrame(screen.visibleFrame, display: true)
                }
            }
            #endif
            // `reveal` is gated on `canTakeInput` while arming computes off-main —
            // an immediate reveal would be silently dropped, so await it.
            Task {
                await viewModel.awaitPendingWork()
                let w = viewModel.boardWidth, h = viewModel.boardHeight
                viewModel.reveal(Coord(w / 2, h / 2))
                await viewModel.awaitPendingWork()
                viewModel.reveal(Coord(w / 2 + 7, h / 2 + 7))
            }
        }
    }

    /// Flush the live game first so the popup's in-progress cues are accurate;
    /// async (an inline XXXL encode stalls), the popup catches up via `savesChanged`.
    func openNewGame() {
        autosave()
        navigator.showingNewGame = true
    }

    /// Clear `pausedForScores` first: the sheet's dismiss handler must not
    /// resume the OLD (now replaced) game.
    private func playFromScoreboard(_ config: GameConfig) {
        pausedForScores = false
        navigator.playConfigRequested = nil
        navigator.showingScores = false
        navigator.showingMessHall = false  // a head-to-head rematch arrives from here
        settings.adopt(config)
        viewModel.newGame(config: config)
        navigator.showingTitle = false
    }

    /// Persist the live game, or clear the save once it's no longer in progress.
    /// Snapshot building scans the whole board — capture the cheap Sendable
    /// inputs on the main actor, do everything else off it.
    func autosave() {
        autosaveTask?.cancel()  // an explicit save subsumes any pending debounce
        if let inputs = viewModel.snapshotInputs() {
            let navigator = navigator
            Task.detached(priority: .utility) {
                guard let snapshot = GameSnapshot(inputs: inputs) else { return }
                await saveWriter.write(snapshot)
                await MainActor.run { navigator.savesChanged &+= 1 }
            }
        } else if viewModel.isPrimedBoard {
            // The player never touched the launch-primed placeholder, so its
            // config's on-disk save is still the real game — leave it be.
        } else {
            let config = viewModel.config
            Task {
                await saveWriter.clear(config: config)
                navigator.savesChanged &+= 1
            }
        }
    }

    /// Never flash: show only if STILL computing after a grace period; once
    /// shown, stay a minimum duration. Input gates on `isComputing` directly —
    /// only the visual waits.
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

    /// For app-exit paths: the process may terminate the instant the handler
    /// returns, so the write must finish inline.
    private func autosaveBlocking() {
        autosaveTask?.cancel()
        defer { navigator.savesChanged &+= 1 }
        if let snapshot = viewModel.snapshot() {
            saveStore.save(snapshot)
        } else if !viewModel.isPrimedBoard {  // never clear for the placeholder
            saveStore.clear(config: viewModel.config)
        }
    }

    /// Coalesce a burst of reveals into one write — a per-move snapshot stalls
    /// a huge board. Periodic/pause/Home/quit saves are the durability backstops.
    private func autosaveSoon() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            autosave()
        }
    }

    /// Enter an attempt on any day's board (today's card, calendar Play).
    func startDailyBoard(_ board: DailyChallenge.Board) {
        navigator.activeDaily = board
        viewModel.newGame(config: board.config, seed: board.seed)
        navigator.showingTitle = false
    }

    /// Retry restarts the SAME board: a daily re-seeds its shared layout
    /// (back into review); a normal game just re-rolls its config.
    func restartGame() {
        if let daily = navigator.activeDaily {
            viewModel.newGame(config: daily.config, seed: daily.seed)
        } else {
            viewModel.newGame()
        }
    }

    /// Home does NOT end the game — pause and save so the Continue card can
    /// resume it; discarding is an explicit New Game.
    func goHome() {
        viewModel.pause()
        autosave()
        navigator.showingTitle = true
    }
}
