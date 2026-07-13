import Foundation

/// The player-scoped Game Center choices, synced via iCloud KVS OUTSIDE the
/// score-sync gate (the shareName-Keychain precedent: small preference state
/// travels; DEVICE-scoped settings like the sync toggle don't). The ASK
/// state merges OR — asked anywhere is asked; the ENABLED state merges
/// last-writer-wins by decision timestamp, because OR would be a ratchet
/// where the opt-out loses every conflict to a stale true.
@MainActor
final class GameCenterPrefs: ObservableObject {
    @Published private(set) var enabled: Bool
    private(set) var asked: Bool

    private let defaults: UserDefaults
    private let kvs: NSUbiquitousKeyValueStore?
    private var enabledAt: TimeInterval
    private var observer: NSObjectProtocol?

    private enum Key {
        static let asked = "donpa.gc.asked"
        static let enabled = "donpa.gc.enabled"
        static let enabledAt = "donpa.gc.enabledAt"
    }

    init(defaults: UserDefaults = .standard, kvs: NSUbiquitousKeyValueStore? = .default) {
        self.defaults = defaults
        self.kvs = kvs
        asked = defaults.bool(forKey: Key.asked)
        enabled = defaults.bool(forKey: Key.enabled)
        enabledAt = defaults.double(forKey: Key.enabledAt)
        if let kvs {
            observer = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: kvs, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.mergeFromCloud() }
            }
            kvs.synchronize()
            mergeFromCloud()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// The player's decision (the toggle, or the ask's Enable): stamp it and
    /// publish — the newest human decision wins everywhere.
    func setEnabled(_ on: Bool) {
        enabled = on
        enabledAt = Date().timeIntervalSince1970
        asked = true
        persistLocal()
        pushToCloud()
    }

    /// The ask was shown and declined — never ask again, on any device.
    func markAsked() {
        guard !asked else { return }
        asked = true
        persistLocal()
        pushToCloud()
    }

    /// The pure merge rules (tested): OR for asked, LWW by stamp for enabled.
    static func mergedAsked(local: Bool, remote: Bool) -> Bool { local || remote }
    static func mergedEnabled(
        local: (on: Bool, at: TimeInterval), remote: (on: Bool, at: TimeInterval)
    ) -> (on: Bool, at: TimeInterval) {
        remote.at > local.at ? remote : local
    }

    private func mergeFromCloud() {
        guard let kvs else { return }
        asked = Self.mergedAsked(local: asked, remote: kvs.bool(forKey: Key.asked))
        let merged = Self.mergedEnabled(
            local: (enabled, enabledAt),
            remote: (kvs.bool(forKey: Key.enabled), kvs.double(forKey: Key.enabledAt)))
        (enabled, enabledAt) = merged
        persistLocal()
    }

    private func persistLocal() {
        defaults.set(asked, forKey: Key.asked)
        defaults.set(enabled, forKey: Key.enabled)
        defaults.set(enabledAt, forKey: Key.enabledAt)
    }

    private func pushToCloud() {
        guard let kvs else { return }
        if asked { kvs.set(true, forKey: Key.asked) }
        kvs.set(enabled, forKey: Key.enabled)
        kvs.set(enabledAt, forKey: Key.enabledAt)
        kvs.synchronize()
    }
}
