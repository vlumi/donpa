import AVFoundation
import Foundation

/// The game's incidental sound effects — short, procedural clips (see
/// `Scripts/assets/make-sounds.swift`) played on flag / chord / reveal / result.
///
/// Preloaded once and kept warm so a tap-to-sound has no load latency. On iOS the
/// audio session is `.ambient` + `.mixWithOthers`, so the hardware Ring/Silent
/// switch mutes the game (as players expect of a puzzle game) and Donpa never
/// interrupts the user's music or podcast. `isEnabled` mirrors the in-app Settings
/// toggle (on by default); with the ringer on, that's the only way to silence it.
@MainActor
final class SoundPlayer {
    enum Effect: String, CaseIterable {
        case flag = "tick"
        /// Opening a tile — also used for a chord (a chord just opens several).
        case reveal
        /// A whole area cascading open: the reveal tick, subtly fuller.
        case flood
        case win
        case lose
    }

    /// The in-app toggle. When false, `play` is a no-op (the ringer switch is the
    /// other mute path on iOS; this one also covers iPad/Mac and ringer-on silence).
    var isEnabled = true

    /// One reusable player per effect. AVAudioPlayer restarts from the top on
    /// `play()` even mid-clip, so rapid taps just retrigger — fine for these
    /// sub-second sounds. Nil for any clip that failed to load (then a silent no-op).
    private var players: [Effect: AVAudioPlayer] = [:]

    init() {
        configureSession()
        for effect in Effect.allCases {
            guard
                let url = Bundle.module.url(forResource: effect.rawValue, withExtension: "caf"),
                let player = try? AVAudioPlayer(contentsOf: url)
            else { continue }
            player.prepareToPlay()  // warm the buffers so the first play isn't late
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
