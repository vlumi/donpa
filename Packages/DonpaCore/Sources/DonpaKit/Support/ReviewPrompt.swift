import Foundation

/// When to spend one of Apple's ~3 review prompts a year: a new personal
/// best (the player is demonstrably pleased), an invested player, and at
/// most once per marketing version. The system may still decline to show.
enum ReviewPrompt {
    static let minimumLifetimeWins = 10

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    static func shouldAsk(newBest: Bool, totalWins: Int, promptedVersion: String, version: String)
        -> Bool
    {
        newBest && totalWins >= minimumLifetimeWins && !version.isEmpty
            && promptedVersion != version
    }
}
