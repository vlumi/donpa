import DonpaCore
import SwiftUI

/// Hand-drawn glyphs for the New Game pager — one per board family (the page
/// tabs) and one per edges choice (the Flat/Round toggle). Same bold-ink Canvas
/// idiom as `MangaIcon`; the picker is graphical by design (the glyph carries
/// the meaning, the caption under it is just a name).
struct BoardGlyph: View {
    enum Kind {
        case basic  // retro window with a mini grid (the original presets)
        case grid  // square lattice
        case hive  // hexagon with a honeycomb junction
        case practice  // shooting-range target — Drills
        case flat  // framed flat map — edges you can fall off
        case round  // globe with wrap bands — the world curves back

        static func family(_ family: BoardFamily) -> Kind {
            switch family {
            case .basic: return .basic
            case .grid: return .grid
            case .hive: return .hive
            case .practice: return .practice
            }
        }

        static func edges(_ edges: BoardEdges) -> Kind {
            edges == .round ? .round : .flat
        }
    }

    let kind: Kind
    var size: CGFloat = 26
    var tint: Color = .primary

    var body: some View {
        Canvas { ctx, area in
            let s = size
            ctx.translateBy(x: (area.width - s) / 2, y: (area.height - s) / 2)
            Self.draw(kind, in: ctx, side: s, color: tint)
        }
        .frame(width: size, height: size)
    }

    /// Stroke styles matching MangaIcon's bold ink.
    private static func strokes(_ s: CGFloat) -> (bold: StrokeStyle, thin: StrokeStyle) {
        let lw = s * 0.09
        return (
            StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round),
            StrokeStyle(lineWidth: lw * 0.7, lineCap: .round, lineJoin: .round)
        )
    }

    /// Per-glyph drawing params, bundled so each helper stays small.
    private struct Pen {
        let ctx: GraphicsContext
        let s: CGFloat
        let ink: GraphicsContext.Shading
        let bold: StrokeStyle
        let thin: StrokeStyle
        func stroke(_ p: Path, thin useThin: Bool = false) {
            ctx.stroke(p, with: ink, style: useThin ? thin : bold)
        }
    }

    static func draw(_ kind: Kind, in ctx: GraphicsContext, side s: CGFloat, color: Color) {
        let (bold, thin) = strokes(s)
        let pen = Pen(
            ctx: ctx, s: s, ink: .color(color), bold: bold, thin: thin)
        switch kind {
        case .basic: drawBasic(pen)
        case .grid: drawGrid(pen)
        case .hive: drawHive(pen)
        case .practice: drawPractice(pen)
        case .flat: drawFlat(pen)
        case .round: drawRound(pen)
        }
    }

    private static func drawBasic(_ pen: Pen) {
        let s = pen.s
        // A retro app window: rounded frame, title-bar line, 2×2 grid below —
        // a nod to where the presets came from.
        let frame = CGRect(x: s * 0.12, y: s * 0.16, width: s * 0.76, height: s * 0.68)
        pen.stroke(Path(roundedRect: frame, cornerRadius: s * 0.08))
        let barY = frame.minY + s * 0.16
        var bar = Path()
        bar.move(to: CGPoint(x: frame.minX, y: barY))
        bar.addLine(to: CGPoint(x: frame.maxX, y: barY))
        pen.stroke(bar, thin: true)
        var cross = Path()
        let midX = frame.midX
        let midY = (barY + frame.maxY) / 2
        cross.move(to: CGPoint(x: midX, y: barY))
        cross.addLine(to: CGPoint(x: midX, y: frame.maxY))
        cross.move(to: CGPoint(x: frame.minX, y: midY))
        cross.addLine(to: CGPoint(x: frame.maxX, y: midY))
        pen.stroke(cross, thin: true)
    }

    private static func drawGrid(_ pen: Pen) {
        let s = pen.s
        // A 3×3 square lattice: the plain open field.
        let frame = CGRect(x: s * 0.14, y: s * 0.14, width: s * 0.72, height: s * 0.72)
        pen.stroke(Path(roundedRect: frame, cornerRadius: s * 0.06))
        var lattice = Path()
        for i in 1...2 {
            let x = frame.minX + frame.width * CGFloat(i) / 3
            let y = frame.minY + frame.height * CGFloat(i) / 3
            lattice.move(to: CGPoint(x: x, y: frame.minY))
            lattice.addLine(to: CGPoint(x: x, y: frame.maxY))
            lattice.move(to: CGPoint(x: frame.minX, y: y))
            lattice.addLine(to: CGPoint(x: frame.maxX, y: y))
        }
        pen.stroke(lattice, thin: true)
    }

    private static func drawHive(_ pen: Pen) {
        let s = pen.s
        // A honeycomb: three pointy-top hexagons sharing edges (one up, two
        // down). NOT a single hexagon with an inner "Y" — that reads as a cube.
        let r = s * 0.21
        let pitch = r * 1.732_050_807_568_877  // √3·r between adjacent centres
        let top = CGPoint(x: s / 2, y: s * 0.31)
        let centres = [
            top,
            CGPoint(x: top.x - pitch / 2, y: top.y + r * 1.5),
            CGPoint(x: top.x + pitch / 2, y: top.y + r * 1.5),
        ]
        var comb = Path()
        for c in centres {
            for i in 0...6 {
                let a = (CGFloat(i) * 60 - 90) * .pi / 180  // pointy-top
                let p = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                if i == 0 { comb.move(to: p) } else { comb.addLine(to: p) }
            }
        }
        pen.stroke(comb)
    }

    private static func drawPractice(_ pen: Pen) {
        let s = pen.s
        // A shooting-range target: two rings + a filled bull. Practice is aiming
        // deliberately — every shot called, no luck involved.
        let c = CGPoint(x: s / 2, y: s / 2)
        let outer = s * 0.38
        pen.stroke(
            Path(
                ellipseIn: CGRect(
                    x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2)))
        let mid = s * 0.23
        pen.stroke(
            Path(ellipseIn: CGRect(x: c.x - mid, y: c.y - mid, width: mid * 2, height: mid * 2)),
            thin: true)
        let bull = s * 0.07
        pen.ctx.fill(
            Path(
                ellipseIn: CGRect(
                    x: c.x - bull, y: c.y - bull, width: bull * 2, height: bull * 2)),
            with: pen.ink)
    }

    private static func drawFlat(_ pen: Pen) {
        let s = pen.s
        // A framed flat map: border frame + two mountain peaks inside. The
        // edge of the frame is the edge of the world.
        let frame = CGRect(x: s * 0.10, y: s * 0.20, width: s * 0.80, height: s * 0.60)
        pen.stroke(Path(roundedRect: frame, cornerRadius: s * 0.05))
        var peaks = Path()
        let base = frame.maxY - s * 0.14
        peaks.move(to: CGPoint(x: frame.minX + s * 0.10, y: base))
        peaks.addLine(to: CGPoint(x: frame.minX + s * 0.26, y: base - s * 0.20))
        peaks.addLine(to: CGPoint(x: frame.minX + s * 0.40, y: base))
        peaks.move(to: CGPoint(x: frame.minX + s * 0.34, y: base))
        peaks.addLine(to: CGPoint(x: frame.minX + s * 0.54, y: base - s * 0.28))
        peaks.addLine(to: CGPoint(x: frame.minX + s * 0.72, y: base))
        pen.stroke(peaks, thin: true)
    }

    private static func drawRound(_ pen: Pen) {
        let s = pen.s
        // A globe with wrap bands: circle + equator + meridian — pan off one
        // side and the world curves back.
        let c = CGPoint(x: s / 2, y: s / 2)
        let r = s * 0.38
        pen.stroke(
            Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)))
        pen.stroke(
            Path(
                ellipseIn: CGRect(
                    x: c.x - r, y: c.y - r * 0.38, width: r * 2, height: r * 0.76)),
            thin: true)
        pen.stroke(
            Path(
                ellipseIn: CGRect(
                    x: c.x - r * 0.38, y: c.y - r, width: r * 0.76, height: r * 2)),
            thin: true)
    }
}
