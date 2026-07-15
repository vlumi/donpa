import DonpaCore
import SwiftUI

/// Holds the long-lived `BoardScene` so SwiftUI builds it exactly once:
/// `@State`'s `initialValue:` is EAGER and re-runs on every re-init (~10×/s
/// from the clock), while `@StateObject`'s autoclosure runs a single time.
@MainActor
final class SceneHolder: ObservableObject {
    let scene: BoardScene
    let soundPlayer = SoundPlayer()
    let hapticPlayer = HapticPlayer()
    init(viewModel: GameViewModel) {
        scene = BoardScene(viewModel: viewModel)
        scene.soundPlayer = soundPlayer
        scene.hapticPlayer = hapticPlayer
    }
}

public struct GameView: View {
    @StateObject private var viewModel: GameViewModel
    @StateObject private var scoreboard: Scoreboard
    @StateObject private var achievements: AchievementStore
    @StateObject private var settings: Settings
    @ObservedObject private var navigator: Navigator
    @StateObject private var friends: FriendsStore
    @StateObject private var dailyStore: DailyStore
    @StateObject private var sceneHolder: SceneHolder
    private var scene: BoardScene { sceneHolder.scene }
    /// Shared with `GameContent` (the writer). Must be stable `@State`: under
    /// `-uitest-clean` a recomputed `ephemeral()` would mint a NEW dir per
    /// access, so reader and writer would never see each other's saves.
    @State private var saveStore: SaveStore =
        SaveStore.isUITestCleanLaunch ? SaveStore.ephemeral() : SaveStore.appSupport()
    private var resumeStore: SaveStore { saveStore }
    /// Cached, refreshed only when a surface that shows them (re)opens — NOT
    /// per body eval: `summaries()` parses every save file, and an XXXL save
    /// is megabytes of JSON.
    @State private var saveSummaries: [SaveStore.SaveSummary] = []
    /// Drives the broken-save alert (OK starts fresh on the same board).
    @State private var failedResumeConfig: GameConfig?
    /// Mirrors the OS launch image so the hand-off into the title is seamless.
    @State private var showSplash = true

    public init(config: GameConfig = .beginner) {
        let syncOn =
            UserDefaults.standard.object(forKey: Settings.syncScoresKey) as? Bool ?? false
        self.init(
            viewModel: GameViewModel(config: config),
            scoreboard: Scoreboard(cloud: UbiquitousStatsStore(), syncEnabled: syncOn),
            settings: Settings(),
            navigator: Navigator())
    }

    /// For a host (e.g. the macOS menu bar) driving the same model/navigation.
    public init(
        viewModel: GameViewModel, scoreboard: Scoreboard, settings: Settings,
        navigator: Navigator
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _scoreboard = StateObject(wrappedValue: scoreboard)
        _settings = StateObject(wrappedValue: settings)
        _navigator = ObservedObject(wrappedValue: navigator)
        // Skipped under -uitest-clean: a clean launch must not adopt a name a
        // previous run synced to the Keychain.
        if !SaveStore.isUITestCleanLaunch {
            settings.shareNameStore = ShareIdentityStore()
        }
        // Friends and feats sync under the SAME syncScores gate as the
        // scoreboard — one social picture.
        let syncOn =
            UserDefaults.standard.object(forKey: Settings.syncScoresKey) as? Bool ?? false
        let achievementStore = AchievementStore(
            cloud: UbiquitousAchievementsStore(), syncEnabled: syncOn)
        _achievements = StateObject(wrappedValue: achievementStore)
        _gameCenter = StateObject(
            wrappedValue: GameCenterReporter(
                prefs: GameCenterPrefs(), achievements: achievementStore,
                scoreboard: scoreboard))
        _friends = StateObject(
            wrappedValue: FriendsStore(
                cloud: UbiquitousFriendsStore(),
                deviceID: DeviceID.current(), syncEnabled: syncOn))
        _dailyStore = StateObject(
            wrappedValue: DailyStore(
                cloud: UbiquitousDailyStore(),
                deviceID: DeviceID.current(), syncEnabled: syncOn))
        _sceneHolder = StateObject(wrappedValue: SceneHolder(viewModel: viewModel))
        // -donpa.gates.fresh: only session wins count, so a veteran tester
        // experiences the fresh ladder without touching their records.
        winsBaseline =
            UnlockGates.freshRun
            ? scoreboard.displayRecords.mapValues(\.wins.total) : [:]
    }

    private let winsBaseline: [String: Int]
    @StateObject private var gameCenter: GameCenterReporter

    public var body: some View {
        ZStack {
            GameContent(
                viewModel: viewModel, scoreboard: scoreboard, settings: settings,
                navigator: navigator, friends: friends, achievements: achievements,
                gameCenter: gameCenter, dailyStore: dailyStore,
                scene: scene, winsBaseline: winsBaseline, saveStore: saveStore)
            // Fade scoped HERE — an imperative `withAnimation` would also
            // animate the chrome's first layout.
            HomeScreen(
                settings: settings,
                snapshots: saveSummaries,
                onContinue: { resume($0) },
                onNewGame: { navigator.showingNewGame = true },
                dailyBoard: todaysBoard,
                dailyDay: todaysBoard.flatMap { dailyStore.displayRecords[$0.dateKey] },
                dailyStreak: (dailyStore.currentStreak(), dailyStore.longestStreak),
                onDaily: { startDaily() },
                onDailyCalendar: { navigator.showingDailyCalendar = true },
                onScores: { navigator.showingScores = true },
                onMessHall: { navigator.showingMessHall = true },
                onSettings: { navigator.showingSettings = true },
                onAbout: { navigator.showingAbout = true },
                onHowTo: { navigator.showingHowTo = true },
                keyboardActive: navigator.showingTitle && !navigator.isModalPresented
            )
            .opacity(navigator.showingTitle ? 1 : 0)
            .allowsHitTesting(navigator.showingTitle)
            .animation(.easeInOut(duration: 0.3), value: navigator.showingTitle)
            .zIndex(1)

            if navigator.showingNewGame {
                NewGamePopup(
                    settings: settings,
                    index: InProgressIndex(savedConfigs: saveSummaries.map(\.config)),
                    gates: UnlockGates(
                        records: scoreboard.displayRecords, winsBaseline: winsBaseline,
                        bypassAll: settings.unlockAll),
                    onStart: { startSelectedGame() },
                    onClose: { navigator.showingNewGame = false },
                    onResume: { resume($0) }
                )
                .transition(.opacity)
                .zIndex(2)
            }

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(3)
                    .task {
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
                    }
            }
        }
        .preferredColorScheme(settings.appearance.colorScheme)
        .animation(.easeInOut(duration: 0.2), value: navigator.showingNewGame)
        // A tapped donpa.app/s/… link (or a Camera Universal Link) arrives here.
        .onOpenURL { receive($0) }
        .modifier(
            ReceivePrompt(
                navigator: navigator, friends: friends, scoreboard: scoreboard,
                settings: settings, dailyStore: dailyStore)
        )
        // An unreadable save is never a silent nothing.
        .alert(
            Text("Couldn't load the saved game", bundle: .module),
            isPresented: Binding(
                get: { failedResumeConfig != nil },
                set: { if !$0 { failedResumeConfig = nil } }),
            presenting: failedResumeConfig
        ) { config in
            Button {
                startFreshAfterFailedResume(config)
                failedResumeConfig = nil
            } label: {
                Text("OK", bundle: .module)
            }
        } message: { _ in
            Text(
                "The save couldn't be read, so a fresh game starts on this board.",
                bundle: .module)
        }
        .onChangeCompat(of: settings.syncScores) {
            scoreboard.syncEnabled = $0
            friends.syncEnabled = $0
            achievements.setSyncEnabled($0)
            dailyStore.syncEnabled = $0
            refreshDeviceRegistry()
        }
        .onChangeCompat(of: navigator.showingTitle) { showing in
            if showing { saveSummaries = resumeStore.summaries() }
        }
        // Retroactive feats (veterans, cloud restores) stamp SILENTLY — no
        // 15-sticker backlog parade; live celebrations only for new earns.
        .task {
            _ = achievements.reconcile(
                derivable: AchievementEngine.derivable(
                    records: scoreboard.displayRecords,
                    longestDailyStreak: dailyStore.longestStreak))
        }
        .onChangeCompat(of: navigator.showingNewGame) { showing in
            if showing { saveSummaries = resumeStore.summaries() }
        }
        // Re-read when a save COMMITS while a surface is up: a big board can
        // still be computing at open, its real save landing seconds later.
        .onChangeCompat(of: navigator.savesChanged) { _ in
            if navigator.showingTitle || navigator.showingNewGame {
                saveSummaries = resumeStore.summaries()
            }
        }
        // UI-test hooks: jump straight to a modal.
        .onAppear {
            saveSummaries = resumeStore.summaries()
            refreshDeviceRegistry()
            LaunchActionRouter.shared.register { handleLaunchAction($0) }
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-uitest-open-newgame") {
                navigator.showingNewGame = true
            }
            if args.contains("-uitest-open-scores") {
                navigator.showingScores = true
            }
        }
    }

    /// App Intents land here (Spotlight / Siri / Shortcuts).
    private func handleLaunchAction(_ action: LaunchActionRouter.Action) {
        navigator.activeDaily = nil
        switch action {
        case .continueBoard:
            let latest = resumeStore.summaries().max { $0.updatedAt < $1.updatedAt }
            guard let config = latest?.config else {
                navigator.showingTitle = true
                return
            }
            resume(config)
        case .startDrills:
            let config = GameConfig.practice(settings.practiceSize)
            settings.adopt(config)
            navigator.showingNewGame = false
            viewModel.newGame(config: config)
            navigator.showingTitle = false
        }
    }

    /// Publish/freshen this device's registry entry (throttled internally).
    private func refreshDeviceRegistry() {
        DeviceRegistry(cloud: UbiquitousDeviceRegistry(), deviceID: DeviceID.current())
            .refreshOwnEntry(syncEnabled: settings.syncScores, describe: DeviceFacts.current)
    }

    private var todaysBoard: DailyChallenge.Board? {
        DailyChallenge.board(for: DailyChallenge.dateKey())
    }

    /// Start (or re-enter) today's board; the review overlay arms via the
    /// gameID change in GameContent.
    private func startDaily() {
        guard let board = todaysBoard else { return }
        navigator.activeDaily = board
        viewModel.newGame(config: board.config, seed: board.seed)
        navigator.showingTitle = false
    }

    private func startSelectedGame() {
        navigator.activeDaily = nil
        navigator.showingNewGame = false
        viewModel.newGame(config: settings.currentConfig)
        navigator.showingTitle = false
    }

    /// An unreadable save (corruption, a between-builds geometry retune)
    /// raises the broken-save alert instead of silently doing nothing.
    private func resume(_ config: GameConfig) {
        guard let snapshot = resumeStore.load(config: config) else {
            failedResumeConfig = config
            return
        }
        navigator.activeDaily = nil
        navigator.showingNewGame = false
        viewModel.restore(from: snapshot)
        navigator.showingTitle = false
    }

    private func startFreshAfterFailedResume(_ config: GameConfig) {
        navigator.activeDaily = nil
        resumeStore.clear(config: config)  // stop it haunting the lists
        saveSummaries = resumeStore.summaries()
        settings.adopt(config)
        navigator.showingNewGame = false
        viewModel.newGame(config: config)
        navigator.showingTitle = false
    }

    /// Classify a received share URL for the receive prompt. Shared by
    /// `onOpenURL` and the QR scanner; verification is in `ShareLink.payload`.
    static func classify(
        _ url: URL, existing: [Friend], ownKey: Data? = nil
    ) -> IncomingShare {
        do {
            let payload = try ShareLink.payload(from: url)
            // Your other device carries the same synced Keychain identity —
            // importing yourself as a rival is never right.
            if let ownKey, payload.publicKey == ownKey { return .own }
            switch FriendMerge.outcome(for: payload, existing: existing) {
            case .nameCollision(let key):
                return .collision(payload, existingKey: key)
            case let outcome:
                return .accepted(payload, outcome)
            }
        } catch let error as ShareCodec.DecodeError {
            return .failed(error)
        } catch {
            return .failed(.notDonpaShare)
        }
    }

    private func receive(_ url: URL) {
        navigator.incomingShare = Self.classify(
            url, existing: friends.friends, ownKey: ShareIdentityStore().identity()?.publicKey)
    }
}

/// The receive flow: a sheet for a verified share, a loud alert for one
/// that failed to verify.
private struct ReceivePrompt: ViewModifier {
    @ObservedObject var navigator: Navigator
    @ObservedObject var friends: FriendsStore
    @ObservedObject var scoreboard: Scoreboard
    @ObservedObject var settings: Settings
    @ObservedObject var dailyStore: DailyStore

    private var isOwn: Bool {
        if case .own = navigator.incomingShare { return true }
        return false
    }

    private var failure: ShareCodec.DecodeError? {
        if case .failed(let error) = navigator.incomingShare { return error }
        return nil
    }

    func body(content: Content) -> some View {
        alerts(sheets(content))
    }

    private func sheets(_ content: Content) -> some View {
        content
            .sheet(item: sheetBinding) { incoming in
                ReceiveShareView(
                    incoming: incoming, friends: friends,
                    onDone: { navigator.incomingShare = nil },
                    // A fresh add lands in the Mess hall so a new rival is never
                    // invisible; deferred a tick (sheet swaps in one turn race).
                    onAdded: {
                        navigator.incomingShare = nil
                        navigator.afterDismiss { navigator.showingMessHall = true }
                    })
            }
            .sheet(isPresented: $navigator.showingMessHall) {
                MessHallView(
                    friends: friends, scoreboard: scoreboard, settings: settings,
                    dailyStore: dailyStore,
                    // Classify and prompt at root, deferred a tick (sheet swap).
                    onScanned: { url in
                        let incoming = GameView.classify(
                            url, existing: friends.friends,
                            ownKey: ShareIdentityStore().identity()?.publicKey)
                        navigator.afterDismiss { navigator.incomingShare = incoming }
                    },
                    onPlay: { navigator.playConfigRequested = $0 })
            }
    }

    private func alerts(_ content: some View) -> some View {
        content
            .alert(
                Text("Couldn't verify share", bundle: .module),
                isPresented: alertBinding,
                presenting: failure
            ) { _ in
                Button {
                    navigator.incomingShare = nil
                } label: {
                    Text("OK", bundle: .module)
                }
            } message: { error in
                Text(error.receiveMessage, bundle: .module)
            }
            .alert(
                Text("That's your own card", bundle: .module),
                isPresented: Binding(
                    get: { isOwn }, set: { if !$0 { navigator.incomingShare = nil } })
            ) {
                Button {
                    navigator.incomingShare = nil
                } label: {
                    Text("OK", bundle: .module)
                }
            } message: {
                Text(
                    """
                    This share was made with your own identity — a rival card \
                    from your other device is still you.
                    """,
                    bundle: .module)
            }
    }

    /// Every incoming case EXCEPT `.failed` (that one is the alert).
    private var sheetBinding: Binding<IncomingShare?> {
        Binding(
            get: { failure == nil ? navigator.incomingShare : nil },
            set: { if $0 == nil { navigator.incomingShare = nil } })
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { failure != nil },
            set: { if !$0 { navigator.incomingShare = nil } })
    }
}
