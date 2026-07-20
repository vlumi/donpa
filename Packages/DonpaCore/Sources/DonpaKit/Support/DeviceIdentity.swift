import DonpaCore
import Foundation

/// The launch-time identity gate: applies a staged fork BEFORE any store
/// initializes (see DeviceFork — stores capture their DeviceID at init), then
/// runs the migration check. Call `bootstrap()` first thing in the App init;
/// clean/demo launches skip it entirely so the harness never touches the real
/// Keychain or identity.
@MainActor
public enum DeviceIdentity {
    /// The launch's migration verdict — `.migrated` drives the one-time
    /// continue-or-fork prompt.
    public private(set) static var launchVerdict: CloneDetection.Verdict = .established

    public static func bootstrap() {
        guard !LaunchStores.isClean else { return }
        let marker = InstallMarkerKeychain()
        DeviceFork.applyIfPending(in: LaunchStores.defaults, marker: marker)
        launchVerdict = CloneDetection.bootstrap(defaults: LaunchStores.defaults, marker: marker)
    }

    /// This install's blob-write stamp; nil in clean/demo runs (no Keychain).
    public static var writerToken: String? {
        LaunchStores.isClean ? nil : InstallMarkerKeychain().read()
    }

    /// The migration prompt's "continue as before".
    public static func continueAsBefore() {
        CloneDetection.acceptContinuation(
            defaults: LaunchStores.defaults, marker: InstallMarkerKeychain())
    }

    /// The migration prompt's (or collision banner's) "start fresh": staged,
    /// applied at the next launch.
    public static func stageFork() {
        DeviceFork.stage(in: LaunchStores.defaults)
    }

    public static var forkPending: Bool {
        DeviceFork.isPending(in: LaunchStores.defaults)
    }
}
