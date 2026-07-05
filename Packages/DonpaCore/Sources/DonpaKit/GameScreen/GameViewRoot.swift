import DonpaCore
import SwiftUI

/// The full game surface: a status bar over a pannable/zoomable SpriteKit board.
/// A thin wrapper that owns the stores and hosts a single long-lived `BoardScene`
/// (which owns all board input natively). `.preferredColorScheme` is applied HERE
/// so the descendant `GameContent` can read the resolved scheme — a view can't
/// observe a scheme it forces on itself, so the read must be below the modifier.
/// Owns the long-lived `BoardScene` so SwiftUI builds it exactly once. `@State`'s
/// `initialValue:` is EAGER — it ran `BoardScene(viewModel:)` on every `GameView.init`,
/// and `GameView` re-inits ~10×/s (the timer republishes `elapsedCentiseconds`), so
/// the app churned out ~one throwaway scene per tick and could leave one leaked,
/// still rendering. `@StateObject`'s autoclosure is evaluated once, so the scene is
/// constructed a single time regardless of how often the view re-inits.
final class SceneHolder: ObservableObject {
    let scene: BoardScene
    init(viewModel: GameViewModel) { scene = BoardScene(viewModel: viewModel) }
}

public struct GameView: View {
    @StateObject private var viewModel: GameViewModel
    @StateObject private var scoreboard: Scoreboard
    @StateObject private var settings: Settings
    @ObservedObject private var navigator: Navigator
    @StateObject private var friends: FriendsStore
    @StateObject private var sceneHolder: SceneHolder
    private var scene: BoardScene { sceneHolder.scene }
    /// The single save store, shared with `GameContent` (which does the writing) so
    /// the popup's resume list / dots read the SAME files the live game writes.
    /// Must be stable `@State`: under `-uitest-clean` it's a fresh ephemeral dir, and
    /// a recomputed `ephemeral()` would mint a NEW dir on every access — so the reader
    /// and writer would never see each other's saves. In production both would resolve
    /// the same App Support dir, but a shared instance keeps them honest either way.
    @State private var saveStore: SaveStore =
        SaveStore.isUITestCleanLaunch ? SaveStore.ephemeral() : SaveStore.appSupport()
    private var resumeStore: SaveStore { saveStore }
    /// Cached in-progress summaries feeding Home's Continue card and the New Game
    /// dots. Refreshed when either surface (re)opens — NOT read per body eval:
    /// `summaries()` parses every save file, and an XXXL save is megabytes of JSON.
    /// The hosts flush pending writes synchronously before opening (goHome /
    /// openNewGame), so a refresh always sees disk truth.
    @State private var saveSummaries: [SaveStore.SaveSummary] = []
    /// A saved board whose file couldn't be read when the player tried to resume
    /// it — drives the broken-save alert (OK starts fresh on the same board).
    @State private var failedResumeConfig: GameConfig?
    /// Brief in-app splash mirroring the OS launch image (which can't be delayed,
    /// being pre-process) so the hand-off into the title is seamless.
    @State private var showSplash = true

    public init(config: GameConfig = .beginner) {
        // Scoreboard iCloud sync is gated by `syncScores` (opt-in, OFF by default);
        // the cloud store also no-ops when signed out.
        let syncOn = UserDefaults.standard.object(forKey: "donpa.syncScores") as? Bool ?? false
        self.init(
            viewModel: GameViewModel(config: config),
            scoreboard: Scoreboard(cloud: UbiquitousStatsStore(), syncEnabled: syncOn),
            settings: Settings(),
            navigator: Navigator())
    }

    /// For a host (e.g. the macOS menu bar) that drives the same view model /
    /// navigation the board renders.
    public init(
        viewModel: GameViewModel, scoreboard: Scoreboard, settings: Settings,
        navigator: Navigator
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _scoreboard = StateObject(wrappedValue: scoreboard)
        _settings = StateObject(wrappedValue: settings)
        _navigator = ObservedObject(wrappedValue: navigator)
        // Friend list + groups sync under the SAME `syncScores` gate as the scoreboard
        // (one social picture), over their own KVS blob namespace + the shared deviceID.
        let syncOn = UserDefaults.standard.object(forKey: "donpa.syncScores") as? Bool ?? false
        _friends = StateObject(
            wrappedValue: FriendsStore(
                cloud: UbiquitousFriendsStore(),
                deviceID: DeviceID.current(), syncEnabled: syncOn))
        // Autoclosure → BoardScene is built once, not on every re-init (see SceneHolder).
        _sceneHolder = StateObject(wrappedValue: SceneHolder(viewModel: viewModel))
    }

    public var body: some View {
        ZStack {
            GameContent(
                viewModel: viewModel, scoreboard: scoreboard, settings: settings,
                navigator: navigator, friends: friends, scene: scene, saveStore: saveStore)
            // Home fade scoped to this overlay via `.animation(_:value:)` — an
            // imperative `withAnimation` would also animate the chrome's first
            // layout, making the status bar visibly settle.
            HomeScreen(
                settings: settings,
                snapshots: saveSummaries,
                onContinue: { resume($0) },
                // Over the still-visible Home — leaving happens on the pick.
                onNewGame: { navigator.showingNewGame = true },
                onScores: { navigator.showingScores = true },
                onMessHall: { navigator.showingMessHall = true },
                onSettings: { navigator.showingSettings = true },
                onAbout: { navigator.showingAbout = true }
            )
            .opacity(navigator.showingTitle ? 1 : 0)
            .allowsHitTesting(navigator.showingTitle)
            .animation(.easeInOut(duration: 0.3), value: navigator.showingTitle)
            .zIndex(1)

            // New Game popup above both board and title (zIndex 2) so the
            // still-visible title can't occlude it. Tap-outside / X / Esc dismiss.
            if navigator.showingNewGame {
                NewGamePopup(
                    settings: settings,
                    onStart: { startSelectedGame() },
                    onClose: { navigator.showingNewGame = false },
                    index: InProgressIndex(savedConfigs: saveSummaries.map(\.config)),
                    onResume: { resume($0) }
                )
                .transition(.opacity)
                .zIndex(2)
            }

            // In-app splash on top (zIndex 3), fading out after a beat.
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
        // A tapped donpa.app/s/… link (or a Universal Link from the Camera) arrives
        // here: decode + classify, then let the receive prompt render the decision.
        .onOpenURL { receive($0) }
        .modifier(
            ReceivePrompt(
                navigator: navigator, friends: friends, scoreboard: scoreboard,
                settings: settings)
        )
        // A saved board that couldn't be read: say so, and offer a fresh start on
        // the same board — never a silent nothing.
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
        // Keep the scoreboard's iCloud-sync gate in step with the Settings toggle.
        .onChangeCompat(of: settings.syncScores) {
            scoreboard.syncEnabled = $0
            friends.syncEnabled = $0
        }
        // Refresh the in-progress summaries whenever a surface that shows them
        // opens (cheap: sidecar summaries, not full saves)…
        .onChangeCompat(of: navigator.showingTitle) { showing in
            if showing { saveSummaries = resumeStore.summaries() }
        }
        .onChangeCompat(of: navigator.showingNewGame) { showing in
            if showing { saveSummaries = resumeStore.summaries() }
        }
        // …and when a save COMMITS while one of those surfaces is up. Big boards
        // can still be computing the first move when the popup opens — the
        // open-time flush has nothing to write yet, and the real save lands via
        // the debounce seconds later. This keeps the dots/Continue live.
        .onChangeCompat(of: navigator.savesChanged) { _ in
            if navigator.showingTitle || navigator.showingNewGame {
                saveSummaries = resumeStore.summaries()
            }
        }
        // UI-test hooks (like -uitest-clean): jump straight to a modal, so
        // tests/screenshots don't depend on tapping through the title.
        .onAppear {
            saveSummaries = resumeStore.summaries()
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-uitest-open-newgame") {
                navigator.showingNewGame = true
            }
            if args.contains("-uitest-open-scores") {
                navigator.showingScores = true
            }
        }
    }

    /// Start a fresh game with the popup's selection and leave Home — the single
    /// entry point for the New Game button and the result screen.
    private func startSelectedGame() {
        navigator.showingNewGame = false
        viewModel.newGame(config: settings.currentConfig)
        navigator.showingTitle = false
    }

    /// Resume a saved board: load its snapshot, restore, and leave Home — shared by
    /// the Home Continue card/list, the art tap, and the New Game popup's Continue.
    /// An unreadable save (corruption, a between-builds geometry retune) raises the
    /// broken-save alert instead of silently doing nothing; its OK starts a fresh
    /// game on the same board.
    private func resume(_ config: GameConfig) {
        guard let snapshot = resumeStore.load(config: config) else {
            failedResumeConfig = config
            return
        }
        navigator.showingNewGame = false
        viewModel.restore(from: snapshot)
        navigator.showingTitle = false
    }

    /// The broken-save follow-up: discard the dead file and start fresh on the same
    /// board (the alert already told the player why).
    private func startFreshAfterFailedResume(_ config: GameConfig) {
        resumeStore.clear(config: config)  // stop it haunting the lists
        saveSummaries = resumeStore.summaries()
        settings.adopt(config)
        navigator.showingNewGame = false
        viewModel.newGame(config: config)
        navigator.showingTitle = false
    }

    /// Decode + verify a received donpa.app/s/… URL, classify it against the current
    /// friends list, and hand the result to the receive prompt. Verification lives in
    /// `ShareLink.payload` (signature) — a throw here means the share is invalid, so
    /// we surface a loud `.failed`; a valid share becomes `.accepted` or `.collision`.
    /// Shared by `onOpenURL` (tapped link) and the scanner (decoded QR).
    static func classify(_ url: URL, existing: [Friend]) -> IncomingShare {
        do {
            let payload = try ShareLink.payload(from: url)
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
        navigator.incomingShare = Self.classify(url, existing: friends.friends)
    }
}

/// Presents the receive flow driven by `Navigator`: the sheet for a verified
/// add/refresh/collision, the loud alert for a share that failed to verify, and the
/// QR scan sheet (whose decoded code routes through the same classify path).
/// A modifier (not inline) so `GameView.body` stays readable.
private struct ReceivePrompt: ViewModifier {
    @ObservedObject var navigator: Navigator
    @ObservedObject var friends: FriendsStore
    @ObservedObject var scoreboard: Scoreboard
    @ObservedObject var settings: Settings

    /// True only for `.failed`, which routes to the alert rather than the sheet.
    private var failure: ShareCodec.DecodeError? {
        if case .failed(let error) = navigator.incomingShare { return error }
        return nil
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: sheetBinding) { incoming in
                ReceiveShareView(
                    incoming: incoming, friends: friends,
                    onDone: { navigator.incomingShare = nil },
                    // A fresh add lands in the Mess hall (deferred a tick — this
                    // sheet is dismissing, and two sheet swaps in one runloop race),
                    // so a new rival is never invisible.
                    onAdded: {
                        navigator.incomingShare = nil
                        Task { @MainActor in navigator.showingMessHall = true }
                    })
            }
            .sheet(isPresented: $navigator.showingMessHall) {
                MessHallView(
                    friends: friends, scoreboard: scoreboard, settings: settings,
                    // A rival URL scanned inside the Mess hall's share sheet: the
                    // view dismissed itself; classify and prompt at root (deferred
                    // a tick for the same sheet-swap reason).
                    onScanned: { url in
                        let incoming = GameView.classify(url, existing: friends.friends)
                        Task { @MainActor in navigator.incomingShare = incoming }
                    })
            }
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
    }

    /// The sheet shows every incoming case EXCEPT `.failed` (which is the alert).
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
