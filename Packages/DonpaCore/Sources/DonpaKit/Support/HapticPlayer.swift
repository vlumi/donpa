#if os(iOS)
import UIKit
#endif

/// Per-move haptics (flag tick, chord thud, dig rumble); the end-of-game
/// success/error haptic lives in `fireHaptic` (GameContent+Result). iOS-only;
/// a no-op elsewhere.
@MainActor
final class HapticPlayer {
    var isEnabled = true

    #if os(iOS)
    // Each method calls `prepare()` right after firing: keeps the next hit's
    // latency low without holding the Taptic Engine on indefinitely.
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    #endif

    func flag() {
        #if os(iOS)
        guard isEnabled else { return }
        light.impactOccurred()
        light.prepare()
        #endif
    }

    func chord() {
        #if os(iOS)
        guard isEnabled else { return }
        medium.impactOccurred()
        medium.prepare()
        #endif
    }

    /// Strength scales with the size of the opened region; `openedCells` is
    /// the reveal delta for this action.
    func reveal(openedCells: Int) {
        #if os(iOS)
        guard isEnabled, openedCells > 0 else { return }
        // 1 cell → ~0.35, saturating for a big cascade (~40+ cells); log keeps
        // small differences feelable without a huge flood maxing instantly.
        let intensity = min(1.0, 0.3 + 0.2 * log2(Double(openedCells) + 1))
        soft.impactOccurred(intensity: intensity)
        soft.prepare()
        #endif
    }
}
