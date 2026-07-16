import DonpaCore
import SwiftUI
import XCTest

@testable import DonpaKit

/// Not a test: an env-gated render harness that writes every medal (all states,
/// light + dark) to PNGs for design review — and later, the ASC export source.
/// Run: DONPA_MEDAL_GALLERY=/path swift test --filter MedalGalleryRender
@MainActor
final class MedalGalleryRender: XCTestCase {
    func testRenderGallery() throws {
        guard let out = ProcessInfo.processInfo.environment["DONPA_MEDAL_GALLERY"] else {
            throw XCTSkip("set DONPA_MEDAL_GALLERY=<dir> to render")
        }
        loadBootAsset()
        let dir = URL(fileURLWithPath: out, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for id in AchievementID.allCases {
            let tiers = id.tierThresholds?.count ?? 1
            var states: [(String, Int)] = [("unearned", 0)]
            for tier in 1...tiers { states.append(("t\(tier)", tier)) }
            for (label, tier) in states {
                for (scheme, name) in [(ColorScheme.light, "light"), (.dark, "dark")] {
                    let view = MedalView(id: id, earnedTier: tier, size: 96)
                        .padding(10)
                        .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.96))
                        .environment(\.colorScheme, scheme)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    guard let image = renderer.nsImage,
                        let tiff = image.tiffRepresentation,
                        let rep = NSBitmapImageRep(data: tiff),
                        let png = rep.representation(using: .png, properties: [:])
                    else {
                        XCTFail("render failed: \(id.rawValue) \(label) \(name)")
                        continue
                    }
                    try png.write(
                        to: dir.appendingPathComponent("\(id.rawValue).\(label).\(name).png"))
                }
            }
        }
    }

    /// The ASC upload set: one 1024×1024 opaque PNG per achievement DEFINITION
    /// (per tier for the ladders), the earned medal on a flat light ground,
    /// named by wire ID so it pairs with the localization sheet. Apple requires
    /// an image even for hidden achievements, so the gags render too.
    /// Run: DONPA_MEDAL_ASC=/path swift test --filter MedalGalleryRender
    func testRenderASCImages() throws {
        guard let out = ProcessInfo.processInfo.environment["DONPA_MEDAL_ASC"] else {
            throw XCTSkip("set DONPA_MEDAL_ASC=<dir> to render the ASC upload set")
        }
        loadBootAsset()
        let dir = URL(fileURLWithPath: out, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for id in AchievementID.allCases {
            let tiers = id.tierThresholds?.count ?? 1
            for tier in 1...tiers {
                // 512pt @2x = 1024px; a flat opaque ground (ASC rejects alpha).
                let view = MedalView(id: id, earnedTier: tier, size: 380)
                    .frame(width: 512, height: 512)
                    .background(Color(white: 0.96))
                    .environment(\.colorScheme, .light)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let cg = renderer.cgImage, let png = flattenedPNG(cg, side: 1024)
                else {
                    XCTFail("ASC render failed: \(id.rawValue) t\(tier)")
                    continue
                }
                let wire = GameCenterMapping.wireID(id, tier: id.tierThresholds == nil ? nil : tier)
                try png.write(to: dir.appendingPathComponent("\(wire).png"))
            }
        }
    }

    /// Composite the rendered CGImage onto an opaque `side`×`side` RGB context —
    /// no alpha channel, which ASC rejects — and PNG-encode. A CoreGraphics
    /// bitmap context with `noneSkipLast` (opaque) drops the channel; the source
    /// already carries an opaque ground, so only the format changes.
    private func flattenedPNG(_ cg: CGImage, side: Int) -> Data? {
        guard
            let ctx = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let flat = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: flat)
        return rep.representation(using: .png, properties: [:])
    }

    /// Headless runs can't resolve SwiftPM asset catalogs — feed the boot asset
    /// straight from its source file (repo-relative; harness-only).
    private func loadBootAsset() {
        if let root = ProcessInfo.processInfo.environment["DONPA_REPO_ROOT"],
            let nsImage = NSImage(
                contentsOf: URL(fileURLWithPath: root).appendingPathComponent(
                    "Packages/DonpaCore/Sources/DonpaKit/Resources/Panels.xcassets/"
                        + "BootPrint.imageset/boot@3x.png"))
        {
            MedalView.bootImageOverride = Image(nsImage: nsImage)
        }
    }
}
