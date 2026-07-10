import DonpaCore
import DonpaKit
import SwiftUI

@main
struct DonpaApp: App {
    @StateObject private var viewModel = GameViewModel()
    @StateObject private var scoreboard = Scoreboard(
        cloud: UbiquitousStatsStore(),
        syncEnabled: UserDefaults.standard.object(forKey: "donpa.syncScores") as? Bool ?? false)
    @StateObject private var settings = Settings()
    @StateObject private var navigator = Navigator()
    @State private var showingAbout = false

    var body: some Scene {
        WindowGroup {
            GameView(
                viewModel: viewModel, scoreboard: scoreboard, settings: settings,
                navigator: navigator
            )
            // Width fits the New Game modal's sidebar options on one row; the
            // height floor keeps the result panel readable. 560 (was 640) so the
            // whole window fits the smallest scaled-display canvases (1024×640
            // logical under "larger text") with the menu + title bars — the modal
            // scrolls when short and the result panel clamps to the board, so
            // nothing clips at the floor. The modal centres itself, so a bigger
            // window just adds margin.
            .frame(minWidth: 680, minHeight: 560)
            .onChange(of: viewModel.config) { _, config in
                WindowSizer.growToFit(for: config)
            }
            .onAppear {
                WindowSizer.growToFit(for: viewModel.config)
            }
            .sheet(isPresented: $showingAbout) { AboutView() }
        }
        .commands {
            // Menu titles are wrapped in explicit `Text(...)` (not the bare
            // `Button("literal")` initializer): SwiftUI's string extractor picks up
            // `Text` literals reliably, whereas the bare-String `Button` init was
            // extracted inconsistently and got flagged `extractionState: stale` on
            // every Xcode open despite being live and translated.
            CommandGroup(replacing: .appInfo) {
                Button {
                    showingAbout = true
                } label: {
                    Text("About Donpa Squad")
                }
                .disabled(modalOpen)
            }
            // Settings lives in the app menu at the standard ⌘, slot (no toolbar
            // gear on macOS). Presented as the in-window sheet via the navigator.
            CommandGroup(replacing: .appSettings) {
                Button {
                    navigator.showingSettings = true
                } label: {
                    Text("Settings…")
                }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(modalOpen)
            }
            CommandGroup(replacing: .newItem) {
                // New Game opens the config popup (pick mode/size, then Start) — the
                // ONLY path to a fresh board, deliberately: the picker is where the
                // families/sizes/densities live, so no preset quick-starts here.
                // Restart replays the same board.
                Button {
                    navigator.showingNewGame = true
                } label: {
                    Text("New Game…")
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(modalOpen)
                Button {
                    viewModel.newGame()
                } label: {
                    Text("Restart Game")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(modalOpen)
                Button {
                    // Pause + save (handled in GameContent), not discard. "Barracks"
                    // is the army vocabulary's name for Home — B for Barracks.
                    navigator.homeRequested &+= 1
                } label: {
                    Text("Barracks")
                }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(modalOpen)
            }
            // Text overload for the same extraction reason as the Buttons above —
            // the bare-literal CommandMenu init was also flagged stale.
            CommandMenu(Text("Game")) {
                Button {
                    navigator.showingScores = true
                } label: {
                    Text("High Scores")
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(modalOpen)

                Divider()

                Button {
                    viewModel.inputMode.toggle()
                } label: {
                    // Two separate literals (not a ternary inside one string) so both
                    // extract as static keys.
                    if viewModel.inputMode == .flag {
                        Text("Switch to Reveal Mode")
                    } else {
                        Text("Switch to Flag Mode")
                    }
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(modalOpen)

                Divider()

                // ⌘0 toggles the corner minimap between its min and max size — it
                // pairs with ⌘+/⌘− as the "fit / actual-size" slot many apps use.
                Button {
                    navigator.toggleMinimapRequested &+= 1
                } label: {
                    Text("Toggle Minimap Size")
                }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(modalOpen)

                // ⌘+ / ⌘− zoom the board (about its centre). Bind zoom-in to the
                // "+" *character*, not a physical key: SwiftUI matches on the char
                // the keystroke produces, so this follows "+" wherever a layout puts
                // it — Finnish ⌘+ (its own key), US ⌘⇧=, JIS ⌘⇧;. Binding to "="
                // instead failed on Finnish, where "=" isn't on that key.
                Button {
                    navigator.zoomInRequested &+= 1
                } label: {
                    Text("Zoom In")
                }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(modalOpen)
                Button {
                    navigator.zoomOutRequested &+= 1
                } label: {
                    Text("Zoom Out")
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(modalOpen)
            }
        }
    }

    /// True while any modal (a navigator sheet/popup, or the macOS About sheet) is
    /// presented — used to disable the menu commands and their keyboard shortcuts
    /// so they don't mutate or navigate the game hidden beneath the modal.
    private var modalOpen: Bool {
        navigator.isModalPresented || showingAbout
    }
}
