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
            // Width fits the New Game modal's sidebar on one row; the height
            // floor keeps the result panel readable while still fitting the
            // smallest scaled-display canvas (1024×640 logical) with the menu
            // and title bars.
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
