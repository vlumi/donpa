#!/usr/bin/env swift
//
// Procedural sound effects — the audio counterpart to the procedural app icon
// and chrome glyphs. Percussive, manga-flavoured, and entirely synthesised: no
// samples, no licensing, tunable by editing the numbers below. Emits four short
// mono CAF files into the DonpaKit resource bundle:
//
//   tick    — flag placed (a bright, tiny click)
//   thud    — a chord fires (a low punchy knock)
//   reveal  — a dig opens cells (one soft blip per action, not per cell)
//   don     — the manga "ドーン!" result sting (a taiko-ish pitch-dropping boom)
//
//   swift Scripts/assets/make-sounds.swift
//
// Deterministic (fixed noise seed), so re-running yields byte-identical files —
// they're committed like the other generated assets. ~35 ms to generate all four.

import AVFoundation
import Foundation

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let outDir = root.appendingPathComponent(
    "Packages/DonpaCore/Sources/DonpaKit/Resources/Sounds")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let sampleRate = 44_100.0

// A tiny deterministic LCG so the noise bursts are identical run to run (the
// files are committed; `Double.random` would churn them every regeneration).
struct SeededNoise {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        // Top 32 bits → [-1, 1).
        return Double(state >> 32) / Double(UInt32.max) * 2 - 1
    }
}

/// Synthesise `seconds` of mono audio with `sample(i, t)` → [-1, 1], and write it
/// as a CAF. A short raised-cosine fade-out on the last 5 ms kills the end click.
func write(_ name: String, seconds: Double, sample: (Int, Double) -> Double) throws {
    let frames = Int(seconds * sampleRate)
    let fadeFrames = min(frames, Int(0.005 * sampleRate))
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
    buffer.frameLength = AVAudioFrameCount(frames)
    let out = buffer.floatChannelData![0]
    for i in 0..<frames {
        let t = Double(i) / sampleRate
        var v = sample(i, t)
        let remaining = frames - i
        if remaining < fadeFrames {
            v *= 0.5 * (1 - cos(.pi * Double(remaining) / Double(fadeFrames)))
        }
        out[i] = Float(max(-1, min(1, v)))
    }
    let url = outDir.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: url)
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
    print("  \(name)")
}

func env(_ t: Double, _ decay: Double) -> Double { exp(-t / decay) }

print("Generating sounds into \(outDir.path):")

var noise = SeededNoise(state: 0x1234_5678)

// tick — a bright, very short click for placing a flag.
try write("tick.caf", seconds: 0.05) { _, t in
    0.55 * sin(2 * .pi * 1_900 * t) * env(t, 0.008)
        + 0.2 * noise.next() * env(t, 0.003)
}

// wipe — clearing a mark (flag→hidden or ?→hidden): a soft DOWNWARD swipe, the
// opposite gesture to the crisp up-tick of placing. Airy noise through a falling
// filter-ish sweep (approximated by a descending tone under a noise bed).
noise = SeededNoise(state: 0x6666_7777)
try write("wipe.caf", seconds: 0.09) { _, t in
    let f = 900 - 500 * (t / 0.09)  // 900 → 400 Hz glide down
    let tone = 0.12 * sin(2 * .pi * f * t) * env(t, 0.05)
    let air = 0.1 * noise.next() * env(t, 0.03)
    return tone + air
}

// reveal — the base "open a tile" tick: a single very short, quiet high blip.
// A chord uses this SAME sound (a chord is just opening several tiles at once),
// so opening always sounds like opening.
try write("reveal.caf", seconds: 0.03) { _, t in
    0.18 * sin(2 * .pi * 1_200 * t) * env(t, 0.006)
}

// flood — the reveal tick with a soft, brief low undertone: the SAME opening
// sound, subtly fuller, for when a whole area cascades open. Special, but not a
// different instrument.
try write("flood.caf", seconds: 0.09) { _, t in
    let tick = 0.18 * sin(2 * .pi * 1_200 * t) * env(t, 0.006)
    let body = 0.16 * sin(2 * .pi * 320 * t) * env(t, 0.055)  // the "area" swell
    return tick + body
}

// win — a bright ASCENDING two-note chime (A5 → E6): success, unmistakably up.
try write("win.caf", seconds: 0.5) { _, t in
    let n1 = 0.5 * sin(2 * .pi * 880 * t) * env(t, 0.18)  // A5
    let n2 = t > 0.09 ? 0.5 * sin(2 * .pi * 1_318.5 * (t - 0.09)) * env(t - 0.09, 0.22) : 0  // E6
    return tanh(1.2 * (n1 + n2))
}

// lose — the ドーン sting: a dark, DESCENDING taiko boom with a skin-slap attack
// and a deep downward pitch sweep. Phase-integrated so the sweep is smooth. The
// falling pitch + low register is the opposite gesture to the win chime.
noise = SeededNoise(state: 0x4444_5555)
var phase = 0.0
try write("lose.caf", seconds: 0.8) { _, t in
    let f = 42 + 38 * env(t, 0.06)  // ~80 Hz → 42 Hz
    phase += 2 * .pi * f / sampleRate
    let boom = 1.1 * sin(phase) * env(t, 0.22)
    let slap = 0.5 * noise.next() * env(t, 0.012)
    let ring = 0.15 * sin(2 * .pi * 160 * t) * env(t, 0.05)
    return tanh(1.8 * (boom + slap + ring)) * 0.95
}

print("Done.")
