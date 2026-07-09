import AVFoundation
import XCTest

@testable import DonpaKit

/// The sound effects are procedural CAF files (Scripts/assets/make-sounds.swift)
/// bundled into DonpaKit. These lock the resource contract — every effect has a
/// loadable clip — and the mute default, without asserting actual playback (which
/// a headless test can't hear).
@MainActor
final class SoundPlayerTests: XCTestCase {

    /// Every Effect case must resolve to a bundled, decodable .caf. A renamed or
    /// missing asset (or a broken generator) fails here rather than silently
    /// no-op'ing in the app.
    func testEveryEffectHasALoadableClip() throws {
        for effect in SoundPlayer.Effect.allCases {
            let url = try XCTUnwrap(
                Bundle.module.url(forResource: effect.rawValue, withExtension: "caf"),
                "missing sound resource: \(effect.rawValue).caf")
            let player = try AVAudioPlayer(contentsOf: url)
            XCTAssertGreaterThan(player.duration, 0, "\(effect.rawValue) has no audio")
            XCTAssertLessThan(
                player.duration, 1.5, "\(effect.rawValue) is longer than an SFX should be")
        }
    }

    /// Constructing the player preloads without throwing, and playing while muted
    /// is a safe no-op (no crash, nothing to assert audibly).
    func testMutedPlayIsANoOp() {
        let player = SoundPlayer()
        player.isEnabled = false
        for effect in SoundPlayer.Effect.allCases { player.play(effect) }
        player.isEnabled = true
        for effect in SoundPlayer.Effect.allCases { player.play(effect) }
    }

    /// Sound is on by default (the ringer switch is the quick mute on iOS).
    func testSoundDefaultsOn() {
        let settings = Settings(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        XCTAssertTrue(settings.sound)
    }
}
