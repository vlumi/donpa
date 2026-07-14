import AVFoundation
import Foundation

/// The game's sound effects — short, procedural clips (see
/// `Scripts/assets/make-sounds.swift`), preloaded once and kept warm so a
/// tap-to-sound has no load latency.
@MainActor
final class SoundPlayer {
    enum Effect: String, CaseIterable {
        case flag = "tick"
        /// Clearing a mark (flag/"?" → hidden): a soft downward swipe.
        case wipe
        /// Opening a tile — also used for a chord (a chord just opens several).
        case reveal
        /// A whole area cascading open: the reveal tick, subtly fuller.
        case flood
        case win
        case lose
    }

    var isEnabled = true

    /// One reusable player per effect: AVAudioPlayer restarts from the top on
    /// `play()` even mid-clip, so rapid taps just retrigger. A clip that failed
    /// to load stays absent and plays as a silent no-op.
    private var players: [Effect: AVAudioPlayer] = [:]

    init() {
        configureSession()
        for effect in Effect.allCases {
            guard
                let url = Bundle.module.url(forResource: effect.rawValue, withExtension: "caf"),
                let player = try? AVAudioPlayer(contentsOf: url)
            else { continue }
            player.prepareToPlay()
            players[effect] = player
        }
    }

    func play(_ effect: Effect) {
        guard isEnabled, let player = players[effect] else { return }
        player.currentTime = 0
        player.play()
    }

    /// `.ambient` = obeys the Ring/Silent switch and never stops other audio;
    /// `.mixWithOthers` lets a podcast keep playing underneath. macOS has no
    /// session concept, so this is iOS-only.
    private func configureSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }
}
