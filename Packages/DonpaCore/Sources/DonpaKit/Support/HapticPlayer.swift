#if os(iOS)
import UIKit
#endif

/// Per-action haptics — the touch counterpart to `SoundPlayer`. In a genre often
/// played muted, a flag *tick*, a chord *thud*, and a cascade *rumble* are much of
/// the feedback. All are short `UIImpactFeedbackGenerator` transients (not a
/// sustained CoreHaptics pattern), so the cost is microjoules — the system
/// keyboard fires more per minute. iOS-only; a no-op elsewhere.
///
/// The end-of-game success/error haptic stays where it is (`fireHaptic` in
/// GameContent+Result) — this covers the in-play moves.
@MainActor
final class HapticPlayer {
    /// Mirrors the Settings toggle; when false, every call is a no-op.
    var isEnabled = true

    #if os(iOS)
    // One generator per weight, kept warm. `prepare()` right before likely use
    // keeps latency low without holding the Taptic Engine on indefinitely.
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    #endif

    /// A crisp tick when a flag (or "?") is placed.
    func flag() {
        #if os(iOS)
        guard isEnabled else { return }
        light.impactOccurred()
        light.prepare()
        #endif
    }

    /// A firmer thud when a chord fires.
    func chord() {
        #if os(iOS)
        guard isEnabled else { return }
        medium.impactOccurred()
        medium.prepare()
        #endif
    }

    /// A soft bump on a dig, its strength scaled by how big the opened region was —
    /// a single cell is a faint tap; a wide flood is a fuller rumble. `openedCells`
    /// is the reveal delta for this action.
    func reveal(openedCells: Int) {
        #if os(iOS)
        guard isEnabled, openedCells > 0 else { return }
        // 1 cell → ~0.35, saturating to full for a big cascade (~40+ cells). log
        // keeps small differences audible-by-touch without a huge flood maxing
        // instantly.
        let intensity = min(1.0, 0.3 + 0.2 * log2(Double(openedCells) + 1))
        soft.impactOccurred(intensity: intensity)
        soft.prepare()
        #endif
    }
}
