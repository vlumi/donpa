import Foundation

extension UserDefaults {
    /// Every store swaps to this wiped suite under `-uitest-clean`, so seeded
    /// demo / UI-test data can never touch the real player's records — the
    /// debug-built demo and the shipped app share a bundle id, and with it a
    /// container and a defaults plist. Wiped once per launch.
    public static let uitestEphemeral: UserDefaults = {
        let name = "fi.misaki.donpa.uitest-ephemeral"
        let suite = UserDefaults(suiteName: name) ?? .standard
        suite.removePersistentDomain(forName: name)
        return suite
    }()
}
