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

// thud — a low, punchy knock when a chord fires (soft-clipped for body).
noise = SeededNoise(state: 0x2222_3333)
try write("thud.caf", seconds: 0.2) { _, t in
    let f = 110 * (1 + 0.6 * env(t, 0.02))  // slight downward pitch bend = punch
    let body = 0.9 * sin(2 * .pi * f * t) * env(t, 0.045)
    let knock = 0.2 * noise.next() * env(t, 0.006)
    return tanh(1.5 * (body + knock))
}

// reveal — a soft, unobtrusive blip per dig action (fires once, not per cell).
try write("reveal.caf", seconds: 0.06) { _, t in
    0.35 * sin(2 * .pi * 760 * t) * env(t, 0.018)
}

// don — the ドーン sting: a taiko-ish boom with a skin-slap attack and a deep
// downward pitch sweep. Phase-integrated so the sweep has no discontinuity.
noise = SeededNoise(state: 0x4444_5555)
var phase = 0.0
try write("don.caf", seconds: 0.8) { _, t in
    let f = 42 + 38 * env(t, 0.06)  // ~80 Hz → 42 Hz
    phase += 2 * .pi * f / sampleRate
    let boom = 1.1 * sin(phase) * env(t, 0.22)
    let slap = 0.5 * noise.next() * env(t, 0.012)
    let ring = 0.15 * sin(2 * .pi * 160 * t) * env(t, 0.05)
    return tanh(1.8 * (boom + slap + ring)) * 0.95
}

print("Done.")
