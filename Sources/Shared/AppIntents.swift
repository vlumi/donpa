import AppIntents
import DonpaKit

struct ContinueBoardIntent: AppIntent {
    static let title: LocalizedStringResource = "Continue My Board"
    static let description = IntentDescription("Resume your most recent game in progress.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        LaunchActionRouter.shared.dispatch(.continueBoard)
        return .result()
    }
}

struct StartDrillsIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Drills"
    static let description = IntentDescription(
        "Start a fresh practice board — no forced guesses.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        LaunchActionRouter.shared.dispatch(.startDrills)
        return .result()
    }
}

struct DonpaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ContinueBoardIntent(),
            phrases: ["Continue my board in \(.applicationName)"],
            shortTitle: "Continue Board",
            systemImageName: "play.fill")
        AppShortcut(
            intent: StartDrillsIntent(),
            phrases: ["Start drills in \(.applicationName)"],
            shortTitle: "Start Drills",
            systemImageName: "target")
    }
}
