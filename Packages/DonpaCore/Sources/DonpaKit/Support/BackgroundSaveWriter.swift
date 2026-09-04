import DonpaCore
import Foundation

/// Runs the expensive encode + atomic write of a `GameSnapshot` off the main
/// thread, so a save on a huge board never stalls input; the caller snapshots
/// on the main actor and hands over the immutable value. The actor serializes
/// writes and clears in call order, so a clear can't race a pending write.
actor BackgroundSaveWriter {
    private let store: SaveStore
    private let dailyStore: SaveStore

    init(store: SaveStore, dailyStore: SaveStore) {
        self.store = store
        self.dailyStore = dailyStore
    }

    /// A daily snapshot (its `dateKey` set) writes to the daily store; a casual
    /// one to the config-keyed store. Routing on the snapshot keeps callers
    /// oblivious to which store a game belongs to.
    func write(_ snapshot: GameSnapshot) {
        (snapshot.dateKey != nil ? dailyStore : store).save(snapshot)
    }

    func clear(config: GameConfig) {
        store.clear(config: config)
    }

    func clear(dateKey: String) {
        dailyStore.clear(dateKey: dateKey)
    }
}
