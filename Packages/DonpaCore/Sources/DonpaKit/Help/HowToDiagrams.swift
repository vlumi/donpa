import DonpaCore
import SpriteKit
import SwiftUI

/// The in-app guide's reusable diagram components. `TileDiagram` is also the
/// planned export seam for the website's board images (rendered headlessly,
/// like MedalGalleryRender).

/// A tiny, ACCURATE board rendering for the help diagrams — the same visual
/// vocabulary as the real board (palette tiles, classic number colours, the
/// flag/mine glyphs), at caption scale.
struct TileDiagram: View {
    enum Tile {
        case hidden
        case revealed(Int)
        case flagged
        case mine
    }

    let rows: [[Tile]]
    var tileSize: CGFloat = 26

    @Environment(\.colorScheme) private var colorScheme
    private var palette: Palette { Palette.resolved(for: colorScheme) }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 2) {
                    ForEach(rows[r].indices, id: \.self) { c in
                        tile(rows[r][c])
                    }
                }
            }
        }
    }

    @ViewBuilder private func tile(_ tile: Tile) -> some View {
        let base = RoundedRectangle(cornerRadius: 3)
        ZStack {
            switch tile {
            case .hidden, .flagged:
                base.fill(Color(skColor: palette.hiddenTile))
            case .revealed, .mine:
                base.fill(Color(skColor: palette.revealedTile))
            }
            switch tile {
            case .hidden:
                EmptyView()
            case .revealed(let n) where n > 0:
                Text(verbatim: "\(n)")
                    .font(.system(size: tileSize * 0.62, weight: .heavy, design: .monospaced))
                    .foregroundStyle(numberColor(n))
            case .revealed:
                EmptyView()
            case .flagged:
                MangaIconView(symbol: .flag, size: tileSize * 0.7)
            case .mine:
                Text(verbatim: "✸")
                    .font(.system(size: tileSize * 0.66, weight: .black))
                    .foregroundStyle(Color(skColor: palette.mineTile))
            }
        }
        .frame(width: tileSize, height: tileSize)
    }

    private func numberColor(_ n: Int) -> Color {
        let index = min(max(n, 1), palette.numbers.count) - 1
        return Color(skColor: palette.numbers[index])
    }
}

/// The mine counter, redrawn at help scale (the status bar's pill).
struct CounterDiagram: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(verbatim: "⚑ 038")
            .font(.system(size: 15, weight: .heavy, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Palette.resolved(for: colorScheme).counter))
    }
}

struct MangaIconView: View {
    let symbol: MangaIcon.Symbol
    var size: CGFloat = 30
    var tint: Color = .primary

    var body: some View {
        Canvas { ctx, area in
            ctx.translateBy(x: (area.width - size) / 2, y: (area.height - size) / 2)
            MangaIcon.draw(symbol, in: ctx, side: size, color: tint)
        }
        .frame(width: size, height: size)
    }
}

struct BoardGlyphView: View {
    let kind: BoardGlyph.Kind
    var size: CGFloat = 30

    var body: some View {
        BoardGlyph(kind: kind, size: size)
    }
}

extension Color {
    /// Bridge the palette's SpriteKit colours into SwiftUI.
    init(skColor: SKColor) {
        #if canImport(UIKit)
        self.init(uiColor: skColor)
        #else
        self.init(nsColor: skColor)
        #endif
    }
}
