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
}
