import DonpaCore
import Foundation

/// The persistence spine for this launch, decided ONCE: real stores normally;
/// under `-uitest-clean` a wiped ephemeral defaults suite and no cloud at all,
/// so demo/UI-test seeding can never touch the real player's data (the
/// debug-built demo shares the shipped app's bundle id, and so its container).
/// Every store construction site routes through this — it is the single gate.
public enum LaunchStores {
    public static let isClean = SaveStore.isUITestCleanLaunch

    /// Where Settings/Scoreboard/Daily/Achievements persist this launch.
    public static let defaults: UserDefaults = isClean ? .uitestEphemeral : .standard

    /// The score-sync toggle — forced OFF under `-uitest-clean` so nothing the
    /// harness seeds can reach iCloud, regardless of the real app's setting.
    public static var syncScores: Bool {
        !isClean
            && (UserDefaults.standard.object(forKey: Settings.syncScoresKey) as? Bool ?? false)
    }

    /// A unique per-launch home for the clean launch's friends file — the real
    /// one lives in Application Support, which the harness must never touch.
    public static func ephemeralFriendsDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("donpa-uitest-friends-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
