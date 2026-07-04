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
    @StateObject private var friends = FriendsStore()
    @StateObject private var sceneHolder: SceneHolder
    private var scene: BoardScene { sceneHolder.scene }
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
        // Autoclosure → BoardScene is built once, not on every re-init (see SceneHolder).
        _sceneHolder = StateObject(wrappedValue: SceneHolder(viewModel: viewModel))
    }

    public var body: some View {
        ZStack {
            GameContent(
                viewModel: viewModel, scoreboard: scoreboard, settings: settings,
                navigator: navigator, scene: scene)
            // Title fade scoped to this overlay via `.animation(_:value:)` — an
            // imperative `withAnimation` would also animate the chrome's first
            // layout, making the status bar visibly settle.
            TitleScreen(
                settings: settings,
                // "Press start": GameContent decides resume vs. New Game (it owns
                // the save), so the tap just signals intent via a counter bump.
                onStart: { navigator.startRequested &+= 1 },
                onSettings: { navigator.showingSettings = true },
                onScores: { navigator.showingScores = true },
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
                    onClose: { navigator.showingNewGame = false }
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
        .modifier(ReceivePrompt(navigator: navigator, friends: friends))
        // Keep the scoreboard's iCloud-sync gate in step with the Settings toggle.
        .onChangeCompat(of: settings.syncScores) { scoreboard.syncEnabled = $0 }
        // UI-test hooks (like -uitest-clean): jump straight to a modal, so
        // tests/screenshots don't depend on tapping through the title.
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-uitest-open-newgame") {
                navigator.showingNewGame = true
            }
            if args.contains("-uitest-open-scores") {
                navigator.showingScores = true
            }
        }
    }

    /// Start a fresh game with the popup's selection and leave the title — the
    /// single entry point for the New Game button, result screen, and title tap.
    private func startSelectedGame() {
        navigator.showingNewGame = false
        viewModel.newGame(config: settings.currentConfig)
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

    /// True only for `.failed`, which routes to the alert rather than the sheet.
    private var failure: ShareCodec.DecodeError? {
        if case .failed(let error) = navigator.incomingShare { return error }
        return nil
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: sheetBinding) { incoming in
                ReceiveShareView(incoming: incoming, friends: friends) {
                    navigator.incomingShare = nil
                }
            }
            .sheet(isPresented: $navigator.showingScanner) {
                ScanShareView { url in
                    // Route on the next runloop tick: the scanner sheet is dismissing,
                    // and presenting the receive sheet in the same tick can race it.
                    let incoming = GameView.classify(url, existing: friends.friends)
                    Task { @MainActor in navigator.incomingShare = incoming }
                }
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
