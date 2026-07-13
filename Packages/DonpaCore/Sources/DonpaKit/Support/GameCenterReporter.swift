import Combine
import DonpaCore
import Foundation
import GameKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Reports decorations to Game Center — strictly OPT-IN (the DECISIONS.md spec):
/// authentication happens only after the player enables it, so GC's sign-in
/// sheet can only ever appear as a consequence of their own choice; GC's
/// banners stay off (the in-game pill is the celebration); no access point;
/// toggling off just stops reporting (GC's all-or-nothing reset is never
/// wired — local decorations are permanent and wipes don't touch them).
/// Every report is a full idempotent snapshot (GameCenterMapping), so a late
/// opt-in reports everything already earned.
@MainActor
final class GameCenterReporter: ObservableObject {
    let prefs: GameCenterPrefs
    private let achievements: AchievementStore
    private let scoreboard: Scoreboard
    private var subscriptions: Set<AnyCancellable> = []
    private var handlerInstalled = false

    var enabled: Bool { prefs.enabled }

    init(prefs: GameCenterPrefs, achievements: AchievementStore, scoreboard: Scoreboard) {
        self.prefs = prefs
        self.achievements = achievements
        self.scoreboard = scoreboard

        // New decorations report promptly; record changes (tier progress)
        // ride a debounce — every game end touches displayRecords.
        achievements.$earned
            .dropFirst()
            .sink { [weak self] _ in self?.reportIfActive() }
            .store(in: &subscriptions)
        scoreboard.$displayRecords
            .dropFirst()
            .debounce(for: .seconds(3), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reportIfActive() }
            .store(in: &subscriptions)
        prefs.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()  // the toggle reads through us
                self?.startIfEnabled()
            }
            .store(in: &subscriptions)

        startIfEnabled()
    }

    /// The toggle / the ask's Enable. Enabling authenticates (lazily) and
    /// retro-reports; disabling just stops.
    func setEnabled(_ on: Bool) {
        prefs.setEnabled(on)
        if on { startIfEnabled() }
    }

    private func startIfEnabled() {
        guard prefs.enabled else { return }
        guard !handlerInstalled else {
            reportIfActive()
            return
        }
        handlerInstalled = true
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, _ in
            Task { @MainActor in
                if let viewController {
                    Self.present(viewController)
                    return
                }
                // Declined or errored: degrade silently (GameKit stops
                // re-prompting on its own; the toggle stays flippable).
                guard GKLocalPlayer.local.isAuthenticated else { return }
                self?.reportIfActive()
            }
        }
    }

    private func reportIfActive() {
        guard prefs.enabled, GKLocalPlayer.local.isAuthenticated else { return }
        let earnedTiers = Dictionary(
            uniqueKeysWithValues: achievements.earned.map { ($0.key, $0.value.keys.max() ?? 0) })
        let snapshot = GameCenterMapping.snapshot(
            earned: earnedTiers, records: scoreboard.displayRecords)
        guard !snapshot.isEmpty else { return }
        let reports = snapshot.map { line -> GKAchievement in
            let achievement = GKAchievement(identifier: line.wireID)
            achievement.percentComplete = line.percent
            achievement.showsCompletionBanner = false  // the in-game pill celebrates
            return achievement
        }
        // Errors stay quiet: the next snapshot is the retry (idempotent).
        GKAchievement.report(reports) { _ in }
    }

    #if os(iOS)
    private static func present(_ viewController: UIViewController) {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        scene?.keyWindow?.rootViewController?
            .present(viewController, animated: true)
    }
    #elseif os(macOS)
    private static func present(_ viewController: NSViewController) {
        NSApp.keyWindow?.contentViewController?.presentAsSheet(viewController)
    }
    #endif
}
