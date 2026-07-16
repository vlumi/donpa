import DonpaCore
import SwiftUI
import XCTest

@testable import DonpaKit

/// Not a test: an env-gated harness that renders the how-to-play guide's board
/// diagrams to PNGs for the website — the real `TileDiagram`, not hand-drawn
/// ASCII, so the site's rules pictures match the app pixel for pixel and
/// regenerate whenever the palette or art changes. Light + dark, @2x.
/// Run: DONPA_GUIDE_DIAGRAMS=/path swift test --filter HowToDiagramRender
@MainActor
final class HowToDiagramRender: XCTestCase {
    typealias Tile = TileDiagram.Tile

    /// One named diagram: the grid(s) to render. A two-board diagram (the
    /// chord before → after) renders both with an arrow between them.
    private struct Diagram {
        let name: String
        let boards: [[[Tile]]]  // one board, or [before, after]
    }

    /// The three guide diagrams, matching the prose in content/how-to-play.md.
    private let diagrams: [Diagram] = [
        // "The goal": a column of hidden mines read off the numbers.
        Diagram(
            name: "goal",
            boards: [
                [
                    [.revealed(0), .revealed(1), .hidden],
                    [.revealed(0), .revealed(2), .hidden],
                    [.revealed(0), .revealed(1), .hidden],
                ]
            ]),
        // "Chording": the 1s satisfied by the flag → chord sweeps the column.
        Diagram(
            name: "chord",
            boards: [
                [
                    [.hidden, .revealed(1), .revealed(0)],
                    [.flagged, .revealed(1), .revealed(0)],
                    [.hidden, .revealed(1), .revealed(0)],
                ],
                [
                    [.revealed(0), .revealed(1), .revealed(0)],
                    [.flagged, .revealed(1), .revealed(0)],
                    [.revealed(0), .revealed(1), .revealed(0)],
                ],
            ]),
        // "Forced guesses": two 1s, two identical candidates, one mine.
        Diagram(
            name: "guess",
            boards: [
                [
                    [.revealed(0), .revealed(1), .hidden],
                    [.revealed(0), .revealed(1), .hidden],
                ]
            ]),
    ]

    func testRenderGuideDiagrams() throws {
        guard let out = ProcessInfo.processInfo.environment["DONPA_GUIDE_DIAGRAMS"] else {
            throw XCTSkip("set DONPA_GUIDE_DIAGRAMS=<dir> to render the guide diagrams")
        }
        let dir = URL(fileURLWithPath: out, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for diagram in diagrams {
            for (scheme, suffix) in [(ColorScheme.light, "light"), (.dark, "dark")] {
                let content = board(diagram, scheme: scheme)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                guard let cg = renderer.cgImage, let png = transparentPNG(cg) else {
                    XCTFail("guide render failed: \(diagram.name) \(suffix)")
                    continue
                }
                try png.write(
                    to: dir.appendingPathComponent("howto-\(diagram.name)-\(suffix).png"))
            }
        }
    }

    /// One or two `TileDiagram`s laid out with a connecting arrow, on a
    /// transparent ground so the site's own page colour shows through.
    @ViewBuilder private func board(_ diagram: Diagram, scheme: ColorScheme) -> some View {
        HStack(spacing: 16) {
            ForEach(diagram.boards.indices, id: \.self) { index in
                if index > 0 {
                    Text(verbatim: "→")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                TileDiagram(rows: diagram.boards[index], tileSize: 34)
            }
        }
        .padding(14)
        .environment(\.colorScheme, scheme)
    }

    /// PNG with the alpha channel kept — the diagrams sit on the page ground,
    /// not a card, so a transparent margin lets either theme show through.
    private func transparentPNG(_ cg: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}
