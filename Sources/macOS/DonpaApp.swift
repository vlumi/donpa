import DonpaCore
import DonpaKit
import SwiftUI

@main
struct DonpaApp: App {
    init() {
        // FIRST: a staged fork must land before any store captures its
        // DeviceID (the @StateObject closures run later, at first render).
        DeviceIdentity.bootstrap()
    }

    @StateObject private var viewModel = GameViewModel()
    // LaunchStores is the single isolation gate: under -uitest-clean these
    // swap to a wiped ephemeral suite with no cloud (see LaunchStores).
    @StateObject private var scoreboard = Scoreboard(
        defaults: LaunchStores.defaults,
        cloud: LaunchStores.isClean ? nil : UbiquitousStatsStore(),
        syncEnabled: LaunchStores.syncScores,
        writerToken: DeviceIdentity.writerToken)
    @StateObject private var settings = Settings(defaults: LaunchStores.defaults)
    @StateObject private var navigator = Navigator()
    @State private var showingAbout = false

    var body: some Scene {
        // A single Window, not a WindowGroup — a WindowGroup answers an
        // incoming share link with a SECOND window over the same game model.
        Window("Donpa Squad", id: "main") {
            GameView(
                viewModel: viewModel, scoreboard: scoreboard, settings: settings,
                navigator: navigator
            )
            // Width fits the New Game modal's sidebar on one row; the height
            // floor keeps the result panel readable while still fitting the
            // smallest scaled-display canvas (1024×640 logical) with the menu
            // and title bars.
            .frame(minWidth: 680, minHeight: 560)
            .screenshotAccent()
            .onChange(of: viewModel.config) { _, config in
                // Demo mode pins a fixed screenshot size — don't let board-fit
                // resize it out from under a capture.
                if !DemoSeed.isRequested { WindowSizer.growToFit(for: config) }
            }
            .onAppear {
                if DemoSeed.isRequested {
                    WindowSizer.fixToScreenshotSize()
                } else {
                    WindowSizer.growToFit(for: viewModel.config)
                }
            }
            .appearanceSheet(isPresented: $showingAbout, settings) { AboutView() }
        }
        .commands {
            // About stays macOS-local — its menu slot is an AppKit concept; the
            // rest of the vocabulary is shared with iPadOS via DonpaCommands.
            CommandGroup(replacing: .appInfo) {
                Button {
                    showingAbout = true
                } label: {
                    Text("About Donpa Squad")
                }
                .disabled(modalOpen)
            }
            DonpaCommands(
                viewModel: viewModel, settings: settings, navigator: navigator,
                modalOpen: modalOpen)
        }
    }

    /// True while any modal (a navigator sheet/popup, or the About sheet) is up —
    /// menu shortcuts are disabled so they can't mutate the game beneath it.
    private var modalOpen: Bool {
        navigator.isModalPresented || showingAbout
    }
}
