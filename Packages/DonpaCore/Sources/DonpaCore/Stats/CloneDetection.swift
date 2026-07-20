import Foundation

/// A per-install token that deliberately does NOT survive a restore onto
/// different hardware (the Keychain impl uses ThisDeviceOnly): "stored
/// DeviceID present, marker gone" is the migration signal, and the token
/// stamps this install's blob writes so two live installs sharing one
/// DeviceID can notice each other. Mockable — the Keychain impl can only
/// run on a device.
public protocol InstallMarkerStore {
    /// The install's token, if this install has minted one on this hardware.
    func read() -> String?
    /// Mint (or replace) the token; returns the new value.
    @discardableResult
    func mint() -> String
}

/// Did this install migrate from other hardware? The DeviceID rides
/// UserDefaults (so it travels with a transfer/restore, and the score data
/// with it — a clean takeover); the install marker rides the Keychain,
/// device-only. Their disagreement is the one observable trace a migration
/// leaves.
public enum CloneDetection {
    public enum Verdict: Equatable {
        /// Nothing stored — a genuinely fresh install.
        case firstRun
        /// ID and marker agree (or a pre-feature install upgraded in place).
        case established
        /// The ID (and data) arrived from other hardware: offer continue/fork.
        case migrated
    }

    /// Set in defaults once a marker has been minted for the stored ID —
    /// travels WITH the data, unlike the marker itself. That asymmetry is
    /// the detector.
    public static let markerMintedKey = "donpa.installMarker.minted"

    public static func assess(
        hasStoredDeviceID: Bool, markerMinted: Bool, markerPresent: Bool
    ) -> Verdict {
        guard hasStoredDeviceID else { return .firstRun }
        // Pre-feature installs have an ID but never minted a marker — an
        // in-place upgrade, not a migration.
        guard markerMinted else { return .established }
        return markerPresent ? .established : .migrated
    }

    /// The launch check: assess, and settle the marker state for the
    /// non-migrated cases (a migration verdict leaves the marker ALONE —
    /// the user's continue/fork choice decides what happens to it).
    public static func bootstrap(
        defaults: UserDefaults, marker: InstallMarkerStore
    ) -> Verdict {
        let verdict = assess(
            hasStoredDeviceID: defaults.string(forKey: DeviceID.defaultsKey) != nil,
            markerMinted: defaults.bool(forKey: markerMintedKey),
            markerPresent: marker.read() != nil)
        switch verdict {
        case .firstRun, .established:
            if marker.read() == nil { marker.mint() }
            defaults.set(true, forKey: markerMintedKey)
        case .migrated:
            break
        }
        return verdict
    }

    /// The migration prompt's "continue as before": adopt this hardware as
    /// the ID's home — mint a fresh marker, keep everything else.
    public static func acceptContinuation(
        defaults: UserDefaults, marker: InstallMarkerStore
    ) {
        marker.mint()
        defaults.set(true, forKey: markerMintedKey)
    }
}
