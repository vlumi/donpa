import Foundation

/// "Start as a new device" — the escape hatch for a cloned install (device
/// migrated, both kept alive) or a handed-on machine. STAGED, then applied
/// at the NEXT launch before any store initializes: every store captures its
/// DeviceID at init, so an in-process switch could push fresh (empty) data
/// under the OLD id and destroy the history the fork exists to preserve.
///
/// Applying reassigns provenance only, never totals: the old blobs stay in
/// the cloud untouched (this never writes to the cloud at all), the local
/// per-device stores reset, and a fresh DeviceID is minted — the next merge
/// shows exactly the same household numbers, with this install now counting
/// under its new identity. Idempotent; a no-op unless staged.
@MainActor
public enum DeviceFork {
    static let pendingKey = "donpa.fork.pending"

    /// Queue the fork for the next launch (the confirm UI's commit).
    public static func stage(in defaults: UserDefaults) {
        defaults.set(true, forKey: pendingKey)
    }

    public static func isPending(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: pendingKey)
    }

    /// Call FIRST at launch, before any store initializes. Returns whether a
    /// staged fork was applied.
    @discardableResult
    public static func applyIfPending(
        in defaults: UserDefaults, marker: InstallMarkerStore
    ) -> Bool {
        guard isPending(in: defaults) else { return false }
        // A fresh id: the next DeviceID.current() mints it. The old blobs
        // (scores, dailies, achievements, friends, registry entry) stay in
        // the cloud under the old id — history keeps its owner.
        defaults.removeObject(forKey: DeviceID.defaultsKey)
        // Mint the new identity NOW, so the forked install reads as
        // established (not a first run) from the very next check.
        _ = DeviceID.current(in: defaults)
        // Local stores whose counters would double-count if republished
        // under the new id reset; union-merged stores (achievements,
        // friends) stay — republishing those is idempotent.
        Scoreboard.forkLocalState(in: defaults)
        DailyStore.forkLocalState(in: defaults)
        // A forked install is, identity-wise, a fresh one.
        marker.mint()
        defaults.set(true, forKey: CloneDetection.markerMintedKey)
        defaults.removeObject(forKey: pendingKey)
        return true
    }
}
