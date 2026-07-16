import DonpaCore
import DonpaKit
import SwiftUI

@main
struct DonpaApp: App {
    // The same store ownership as the macOS app, so the shared menu commands
    // (the iPadOS hold-⌘ HUD + hardware-keyboard shortcuts) can drive the game.
    @StateObject private var viewModel = GameViewModel()
    @StateObject private var scoreboard = Scoreboard(
        cloud: UbiquitousStatsStore(),
        syncEnabled: UserDefaults.standard.object(forKey: "donpa.syncScores") as? Bool ?? false)
    @StateObject private var settings = Settings()
    @StateObject private var navigator = Navigator()

    var body: some Scene {
        WindowGroup {
            GameView(
                viewModel: viewModel, scoreboard: scoreboard, settings: settings,
                navigator: navigator
            )
            .screenshotAccent()
        }
        .commands {
            DonpaCommands(
                viewModel: viewModel, settings: settings, navigator: navigator,
                modalOpen: navigator.isModalPresented)
        }
    }
}
