import DonpaCore
import SwiftUI

/// One decoration: the shared medal chassis around a per-feat emblem — also the
/// single source the ASC achievement images are exported from. Unearned renders
/// as a silhouette; hidden feats keep a "?" until earned.
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

        // The chassis is an abstract naval mine: eight stubby contact horns.
        var horns = Path()
        for i in 0..<8 {
            // Offset half a step so no horn points straight up.
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

        let disc = Path(
            ellipseIn: CGRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2))
        if earned, let thresholds = id.tierThresholds {
            ctx.fill(
                disc,
                with: .color(Self.metal(for: earnedTier, of: thresholds.count).opacity(0.30)))
        }
        ctx.stroke(disc, with: .color(ink), style: StrokeStyle(lineWidth: lw))

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

    /// Metals anchor at the top: a feat's highest tier is always gold, with
    /// silver then bronze counting down beneath it.
    static func metal(for tier: Int, of total: Int) -> Color {
        switch total - tier {
        case 0: return Color(red: 0.85, green: 0.65, blue: 0.13)  // gold
        case 1: return Color(red: 0.62, green: 0.66, blue: 0.71)  // silver
        default: return Color(red: 0.72, green: 0.45, blue: 0.20)  // bronze
        }
    }

    static var gold: Color { metal(for: 1, of: 1) }

    // MARK: Emblems

    private static func drawEmblem(
        _ id: AchievementID, in ctx: GraphicsContext, side s: CGFloat, ink: Color
    ) {
        emblems[id]?(ctx, s, ink)
    }

    /// One drawer per feat — a table, not a 22-arm switch, for the lint budget.
    private static let emblems: [AchievementID: (GraphicsContext, CGFloat, Color) -> Void] = [
        // The real boot-print asset; MangaIcon's Canvas boot path renders as a blob.
        .winFirst: { ctx, s, ink in
            bootAsset(
                in: ctx,
                placement: .init(
                    center: CGPoint(x: s / 2, y: s / 2), height: s * 0.96, rotation: -12),
                ink: ink)
        },
        .drillsL: { BoardGlyph.draw(.practice, in: $0, side: $1, color: $2) },
        .hiveFirst: { BoardGlyph.draw(.hive, in: $0, side: $1, color: $2) },
        .roundFirst: { BoardGlyph.draw(.round, in: $0, side: $1, color: $2) },
        // One big cell with the star inside — must stay distinct from Into the Hive.
        .hiveInsane: { ctx, s, ink in
            hexagon(in: ctx, at: CGPoint(x: s / 2, y: s / 2), radius: s * 0.42, ink: ink)
            star(in: ctx, at: CGPoint(x: s / 2, y: s / 2), radius: s * 0.20, ink: ink)
        },
        // Faded flag behind the no-sign — the same grammar as Bomb Squad.
        .purityNoFlag: { ctx, s, ink in
            var inner = ctx
            inner.translateBy(x: s * 0.08, y: s * 0.06)
            pennant(in: inner, side: s * 0.86, ink: ink.opacity(0.6))
            noSign(in: ctx, side: s, ink: ink)
        },
        .speedExpert: { stopwatch(in: $0, side: $1, ink: $2) },
        .insaneWin: { ctx, s, ink in
            star(in: ctx, at: CGPoint(x: s / 2, y: s / 2), radius: s * 0.34, ink: ink)
        },
        .lunaticWin: { fullMoon(in: $0, side: $1, ink: $2) },
        .luckCoinFlip: { coin(in: $0, side: $1, label: "1/2", ink: $2) },
        .fullClearSize: { BoardGlyph.draw(.grid, in: $0, side: $1, color: $2) },
        .trifecta: { BoardGlyph.draw(.basic, in: $0, side: $1, color: $2) },
        .trifectaTime: { ctx, s, ink in
            BoardGlyph.draw(.basic, in: ctx, side: s, color: ink)
            stopwatch(
                in: ctx, side: s * 0.45, at: CGPoint(x: s * 0.74, y: s * 0.26), ink: ink)
        },
        .milesWins: { MangaIcon.draw(.flag, in: $0, side: $1, color: $2) },
        .milesTiles: { ctx, s, ink in
            bootAsset(
                in: ctx,
                placement: .init(
                    center: CGPoint(x: s * 0.30, y: s * 0.60), height: s * 0.62,
                    rotation: 10, mirrored: true),
                ink: ink)
            bootAsset(
                in: ctx,
                placement: .init(
                    center: CGPoint(x: s * 0.72, y: s * 0.40), height: s * 0.62,
                    rotation: -10),
                ink: ink)
        },
        .milesDisarmed: { ctx, s, ink in
            // Keep the mine well inside the ring — spikes touching the circle
            // read as a spoked wheel.
            var inner = ctx
            inner.translateBy(x: s * 0.19, y: s * 0.19)
            mine(in: inner, side: s * 0.62, ink: ink.opacity(0.6))
            noSign(in: ctx, side: s, ink: ink)
        },
        .hiddenSecond: { ctx, s, ink in
            burst(in: ctx, side: s, ink: ink)
            label("2", in: ctx, side: s, ink: ink, scale: 0.34)
        },
        .hiddenThirteen: { ctx, s, ink in
            circleFace(in: ctx, side: s, ink: ink)
            label("13", in: ctx, side: s, ink: ink)
        },
        .hiddenSoClose: { label("99%", in: $0, side: $1, ink: $2) },
        .hiddenOvertime: { infinity(in: $0, side: $1, ink: $2) },
    ]

}
