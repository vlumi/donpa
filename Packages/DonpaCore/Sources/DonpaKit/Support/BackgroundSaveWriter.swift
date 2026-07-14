import DonpaCore
import Foundation

/// Runs the expensive encode + atomic write of a `GameSnapshot` off the main
/// thread, so a save on a huge board never stalls input; the caller snapshots
/// on the main actor and hands over the immutable value. The actor serializes
/// writes and clears in call order, so a clear can't race a pending write.
actor BackgroundSaveWriter {
    private let store: SaveStore

    init(store: SaveStore) {
        self.store = store
    }

    func write(_ snapshot: GameSnapshot) {
        store.save(snapshot)
    }

    func clear(config: GameConfig) {
        store.clear(config: config)
    }
}
