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

    // The same store ownership as the macOS app, so the shared menu commands
    // (the iPadOS hold-⌘ HUD + hardware-keyboard shortcuts) can drive the game.
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
