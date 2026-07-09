import DonpaCore
import SwiftUI

/// One decoration: the shared medal chassis (ring + ribbon tabs, metal tinted
/// by the earned tier on tiered feats) around a per-feat emblem — same
/// bold-ink Canvas idiom as `MangaIcon`/`BoardGlyph`, and the single source
/// the ASC images will be exported from. Unearned renders as a silhouette;
/// hidden feats keep a "?" until earned.
struct MedalView: View {
    let id: AchievementID
    /// Highest earned tier (0 = unearned; one-shots earn at 1).
    let earnedTier: Int
    var size: CGFloat = 56

    private var earned: Bool { earnedTier > 0 }

    var body: some View {
        Canvas { ctx, area in
            let s = size
            ctx.translateBy(x: (area.width - s) / 2, y: (area.height - s) / 2)
            Self.draw(
                id, earnedTier: earnedTier, in: ctx, side: s,
                ink: earned ? Color.primary : Color.primary.opacity(0.35))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)  // the grid cell carries the spoken info
    }

    // MARK: Chassis

    static func draw(
        _ id: AchievementID, earnedTier: Int, in ctx: GraphicsContext, side s: CGFloat,
        ink: Color
    ) {
        let earned = earnedTier > 0
        let center = CGPoint(x: s / 2, y: s / 2)
        let radius = s * 0.34
        let lw = s * 0.05

        // The chassis is an abstract naval mine (user call — the ribbon tabs
        // read as Sputnik): eight stubby contact horns around the disc. The
        // one shape that makes a Minesweeper decoration self-explanatory.
        var horns = Path()
        for i in 0..<8 {
            // Offset half a step so no horn points straight up (less antenna).
            let angle = (CGFloat(i) + 0.5) * .pi / 4
            let from = CGPoint(
                x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            let to = CGPoint(
                x: center.x + (radius + s * 0.09) * cos(angle),
                y: center.y + (radius + s * 0.09) * sin(angle))
            horns.move(to: from)
            horns.addLine(to: to)
        }
        ctx.stroke(
            horns, with: .color(ink),
            style: StrokeStyle(lineWidth: lw * 1.5, lineCap: .round))

        // The disc: metal fill for earned tiers, paper otherwise.
        let disc = Path(
            ellipseIn: CGRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2))
        if earned, id.tierThresholds != nil {
            ctx.fill(disc, with: .color(Self.metal(for: earnedTier).opacity(0.30)))
        }
        ctx.stroke(disc, with: .color(ink), style: StrokeStyle(lineWidth: lw))

        // The emblem, centred in the disc.
        let emblemSide = radius * 1.15
        var inner = ctx
        inner.translateBy(x: center.x - emblemSide / 2, y: center.y - emblemSide / 2)
        if id.isHidden && !earned {
            inner.draw(
                Text(verbatim: "?").font(.system(size: emblemSide * 0.9, weight: .black))
                    .foregroundColor(ink),
                at: CGPoint(x: emblemSide / 2, y: emblemSide / 2))
        } else {
            Self.drawEmblem(id, in: inner, side: emblemSide, ink: ink)
        }
    }

    /// Bronze / silver / gold by earned tier (capped — a 3-tier feat's top is gold).
    static func metal(for tier: Int) -> Color {
        switch tier {
        case 1: return Color(red: 0.72, green: 0.45, blue: 0.20)
        case 2: return Color(red: 0.62, green: 0.66, blue: 0.71)
        default: return Color(red: 0.85, green: 0.65, blue: 0.13)
        }
    }

    // MARK: Emblems (the per-feat centre; see the spec's emblem table)

    private static func drawEmblem(
        _ id: AchievementID, in ctx: GraphicsContext, side s: CGFloat, ink: Color
    ) {
        emblems[id]?(ctx, s, ink)
    }

    /// One drawer per feat (table, not a 22-arm switch — the lint budget), each
    /// composed from the shared parts below and the app's existing glyphs.
    private static let emblems: [AchievementID: (GraphicsContext, CGFloat, Color) -> Void] = [
        .winFirst: { MangaIcon.draw(.reveal, in: $0, side: $1, color: $2) },
        .drillsL: { BoardGlyph.draw(.practice, in: $0, side: $1, color: $2) },
        .hiveFirst: { BoardGlyph.draw(.hive, in: $0, side: $1, color: $2) },
        .roundFirst: { BoardGlyph.draw(.round, in: $0, side: $1, color: $2) },
        .hiveInsane: { ctx, s, ink in
            BoardGlyph.draw(.hive, in: ctx, side: s, color: ink)
            star(in: ctx, at: CGPoint(x: s / 2, y: s * 0.52), radius: s * 0.16, ink: ink)
        },
        .purityNoFlag: { ctx, s, ink in
            MangaIcon.draw(.flag, in: ctx, side: s, color: ink)
            slash(in: ctx, side: s, ink: ink)
        },
        .speedExpert: { stopwatch(in: $0, side: $1, ink: $2) },
        .insaneWin: { ctx, s, ink in
            star(in: ctx, at: CGPoint(x: s / 2, y: s / 2), radius: s * 0.34, ink: ink)
        },
        .lunaticWin: { crescent(in: $0, side: $1, ink: $2) },
        .luckCoinFlip: { coin(in: $0, side: $1, label: "1/2", ink: $2) },
        .luckLongShot: { coin(in: $0, side: $1, label: "1/3", ink: $2) },
        .luckMiracle: { coin(in: $0, side: $1, label: "1/4", ink: $2) },
        .fullClearSize: { BoardGlyph.draw(.grid, in: $0, side: $1, color: $2) },
        .trifecta: { BoardGlyph.draw(.basic, in: $0, side: $1, color: $2) },
        .trifectaTime: { ctx, s, ink in
            BoardGlyph.draw(.basic, in: ctx, side: s, color: ink)
            stopwatch(
                in: ctx, side: s * 0.45, at: CGPoint(x: s * 0.74, y: s * 0.26), ink: ink)
        },
        .milesWins: { MangaIcon.draw(.flag, in: $0, side: $1, color: $2) },
        .milesTiles: { ctx, s, ink in
            var trail = ctx
            trail.translateBy(x: -s * 0.14, y: -s * 0.10)
            MangaIcon.draw(.reveal, in: trail, side: s * 0.7, color: ink)
            var second = ctx
            second.translateBy(x: s * 0.28, y: s * 0.34)
            MangaIcon.draw(.reveal, in: second, side: s * 0.7, color: ink)
        },
        .milesDisarmed: { ctx, s, ink in
            mine(in: ctx, side: s, ink: ink)
            slash(in: ctx, side: s, ink: ink)
        },
        .hiddenSecond: { ctx, s, ink in
            mine(in: ctx, side: s, ink: ink)
            label("2", in: ctx, side: s, ink: ink)
        },
        .hiddenThirteen: { ctx, s, ink in
            circleFace(in: ctx, side: s, ink: ink)
            label("13", in: ctx, side: s, ink: ink)
        },
        .hiddenSoClose: { label("99%", in: $0, side: $1, ink: $2) },
        .hiddenOvertime: { label("∞", in: $0, side: $1, ink: $2, scale: 0.8) },
    ]

    // MARK: Emblem parts

    private static func slash(in ctx: GraphicsContext, side s: CGFloat, ink: Color) {
        var line = Path()
        line.move(to: CGPoint(x: s * 0.08, y: s * 0.92))
        line.addLine(to: CGPoint(x: s * 0.92, y: s * 0.08))
        ctx.stroke(
            line, with: .color(ink),
            style: StrokeStyle(lineWidth: s * 0.10, lineCap: .round))
    }

    private static func star(
        in ctx: GraphicsContext, at c: CGPoint, radius r: CGFloat, ink: Color
    ) {
        var path = Path()
        for i in 0..<10 {
            let angle = (CGFloat(i) * 36 - 90) * .pi / 180
            let radiusAt = i.isMultiple(of: 2) ? r : r * 0.45
            let p = CGPoint(x: c.x + radiusAt * cos(angle), y: c.y + radiusAt * sin(angle))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        ctx.fill(path, with: .color(ink))
    }

    private static func crescent(in ctx: GraphicsContext, side s: CGFloat, ink: Color) {
        var moon = Path(
            ellipseIn: CGRect(x: s * 0.14, y: s * 0.10, width: s * 0.72, height: s * 0.80))
        moon.addEllipse(
            in: CGRect(x: s * 0.34, y: s * 0.06, width: s * 0.66, height: s * 0.72))
        ctx.fill(moon, with: .color(ink), style: FillStyle(eoFill: true))
    }

    private static func stopwatch(
        in ctx: GraphicsContext, side s: CGFloat, at c: CGPoint? = nil, ink: Color
    ) {
        let center = c ?? CGPoint(x: s / 2, y: s * 0.56)
        let r = s * 0.34
        let lw = s * 0.08
        ctx.stroke(
            Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
            with: .color(ink), style: StrokeStyle(lineWidth: lw))
        var parts = Path()
        parts.move(to: CGPoint(x: center.x, y: center.y - r - s * 0.10))  // crown
        parts.addLine(to: CGPoint(x: center.x, y: center.y - r))
        parts.move(to: center)  // hand
        parts.addLine(to: CGPoint(x: center.x + r * 0.55, y: center.y - r * 0.4))
        ctx.stroke(parts, with: .color(ink), style: StrokeStyle(lineWidth: lw, lineCap: .round))
    }

    private static func coin(
        in ctx: GraphicsContext, side s: CGFloat, label text: String, ink: Color
    ) {
        let inset = s * 0.08
        let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
        ctx.stroke(
            Path(ellipseIn: rect), with: .color(ink), style: StrokeStyle(lineWidth: s * 0.08))
        label(text, in: ctx, side: s, ink: ink, scale: 0.42)
    }

    private static func mine(in ctx: GraphicsContext, side s: CGFloat, ink: Color) {
        let c = CGPoint(x: s / 2, y: s / 2)
        let r = s * 0.26
        ctx.fill(
            Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
            with: .color(ink))
        var spikes = Path()
        for i in 0..<8 {
            let angle = CGFloat(i) * 45 * .pi / 180
            spikes.move(to: CGPoint(x: c.x + r * cos(angle), y: c.y + r * sin(angle)))
            spikes.addLine(
                to: CGPoint(x: c.x + r * 1.6 * cos(angle), y: c.y + r * 1.6 * sin(angle)))
        }
        ctx.stroke(
            spikes, with: .color(ink),
            style: StrokeStyle(lineWidth: s * 0.06, lineCap: .round))
    }

    private static func circleFace(in ctx: GraphicsContext, side s: CGFloat, ink: Color) {
        let inset = s * 0.10
        let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
        ctx.stroke(
            Path(ellipseIn: rect), with: .color(ink), style: StrokeStyle(lineWidth: s * 0.07))
    }

    private static func label(
        _ text: String, in ctx: GraphicsContext, side s: CGFloat, ink: Color,
        scale: CGFloat = 0.5
    ) {
        ctx.draw(
            Text(verbatim: text)
                .font(.system(size: s * scale, weight: .black, design: .rounded))
                .foregroundColor(ink),
            at: CGPoint(x: s / 2, y: s / 2))
    }
}
