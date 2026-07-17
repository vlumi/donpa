import DonpaCore
import SwiftUI

/// Shared emblem shapes the per-feat drawers in `MedalView.emblems` compose
/// (split from the medal for the type-length budget).
extension MedalView {
    static func star(
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

    /// Test seam: headless XCTest/ImageRenderer can't resolve SwiftPM asset
    /// catalogs, so the gallery harness injects the asset loaded from its file.
    static var bootImageOverride: Image?

    /// Where a print sits. The asset is portrait (~1:2), so it's sized by height.
    struct PrintPlacement {
        var center: CGPoint
        var height: CGFloat
        var rotation: Double
        var mirrored = false
    }

    static func bootAsset(
        in ctx: GraphicsContext, placement: PrintPlacement, ink: Color
    ) {
        let (center, height, rotation, mirrored) =
            (placement.center, placement.height, placement.rotation, placement.mirrored)
        var inner = ctx
        inner.translateBy(x: center.x, y: center.y)
        inner.rotate(by: .degrees(mirrored ? -rotation : rotation))
        if mirrored { inner.scaleBy(x: -1, y: 1) }
        let image = bootImageOverride ?? Image("BootPrint", bundle: .module)
        let resolved = inner.resolve(image)
        let width = height * 0.52
        let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
        // Tint by masking (fill ink through the image's alpha) — template-mode
        // shading is unreliable across resolve paths and can leave the asset's
        // own white on light backgrounds.
        inner.clipToLayer { mask in
            mask.draw(resolved, in: rect)
        }
        inner.fill(Path(rect), with: .color(ink))
    }

    /// A pointy-top hexagon outline.
    static func hexagon(
        in ctx: GraphicsContext, at c: CGPoint, radius r: CGFloat, ink: Color
    ) {
        var path = Path()
        for i in 0...6 {
            let a = (CGFloat(i) * 60 - 90) * .pi / 180
            let p = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        ctx.stroke(
            path, with: .color(ink), style: StrokeStyle(lineWidth: r * 0.22, lineJoin: .round))
    }

    static func pennant(in ctx: GraphicsContext, side s: CGFloat, ink: Color) {
        var pole = Path()
        pole.move(to: CGPoint(x: s * 0.30, y: s * 0.12))
        pole.addLine(to: CGPoint(x: s * 0.30, y: s * 0.90))
        ctx.stroke(
            pole, with: .color(ink), style: StrokeStyle(lineWidth: s * 0.08, lineCap: .round))
        var flag = Path()
        flag.move(to: CGPoint(x: s * 0.30, y: s * 0.14))
        flag.addLine(to: CGPoint(x: s * 0.82, y: s * 0.28))
        flag.addLine(to: CGPoint(x: s * 0.30, y: s * 0.44))
        flag.closeSubpath()
        ctx.fill(flag, with: .color(ink))
    }

    static func fullMoon(in ctx: GraphicsContext, side s: CGFloat, ink: Color) {
        let inset = s * 0.10
        let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
        // The faint fill makes the moon luminous in dark mode (glow behind the
        // outline); in light mode it's a wash and the outline carries the shape.
        ctx.fill(Path(ellipseIn: rect), with: .color(ink.opacity(0.25)))
        ctx.stroke(
            Path(ellipseIn: rect), with: .color(ink), style: StrokeStyle(lineWidth: s * 0.08))
        for (x, y, r) in [(0.38, 0.36, 0.09), (0.60, 0.52, 0.12), (0.42, 0.66, 0.07)] {
            let crater = CGRect(
                x: s * x - s * r, y: s * y - s * r, width: s * r * 2, height: s * r * 2)
            ctx.fill(Path(ellipseIn: crater), with: .color(ink.opacity(0.4)))
        }
    }

    /// The universal no-sign, drawn over a faded subject.
    static func noSign(in ctx: GraphicsContext, side s: CGFloat, ink: Color) {
        let inset = s * 0.05
        let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
        var path = Path(ellipseIn: rect)
        path.move(to: CGPoint(x: s * 0.22, y: s * 0.22))
        path.addLine(to: CGPoint(x: s * 0.78, y: s * 0.78))
        ctx.stroke(
            path, with: .color(ink), style: StrokeStyle(lineWidth: s * 0.09, lineCap: .round))
    }

    static func burst(in ctx: GraphicsContext, side s: CGFloat, ink: Color) {
        let c = CGPoint(x: s / 2, y: s / 2)
        var path = Path()
        for i in 0..<16 {
            let a = CGFloat(i) * .pi / 8 - .pi / 2
            let r = i.isMultiple(of: 2) ? s * 0.48 : s * 0.27
            let p = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        ctx.stroke(
            path, with: .color(ink), style: StrokeStyle(lineWidth: s * 0.06, lineJoin: .round))
    }

    /// A bound calendar page with a bold check across its day grid — the
    /// daily-participation motif (rings on top, a header band, a tick).
    static func calendarPage(in ctx: GraphicsContext, side s: CGFloat, ink: Color) {
        let line = StrokeStyle(lineWidth: s * 0.055, lineJoin: .round)
        let page = CGRect(x: s * 0.16, y: s * 0.22, width: s * 0.68, height: s * 0.62)
        var path = Path(roundedRect: page, cornerRadius: s * 0.06)
        // Header band under the binding.
        path.move(to: CGPoint(x: page.minX, y: page.minY + s * 0.16))
        path.addLine(to: CGPoint(x: page.maxX, y: page.minY + s * 0.16))
        ctx.stroke(path, with: .color(ink), style: line)
        // Binding rings.
        var rings = Path()
        for x in [page.minX + page.width * 0.28, page.minX + page.width * 0.72] {
            rings.move(to: CGPoint(x: x, y: page.minY + s * 0.04))
            rings.addLine(to: CGPoint(x: x, y: page.minY - s * 0.08))
        }
        ctx.stroke(
            rings, with: .color(ink),
            style: StrokeStyle(lineWidth: s * 0.06, lineCap: .round))
        // The check, floated in the day area with a margin off every edge.
        var check = Path()
        check.move(to: CGPoint(x: page.minX + page.width * 0.28, y: page.minY + s * 0.40))
        check.addLine(to: CGPoint(x: page.minX + page.width * 0.44, y: page.maxY - s * 0.16))
        check.addLine(to: CGPoint(x: page.maxX - page.width * 0.22, y: page.minY + s * 0.30))
        ctx.stroke(
            check, with: .color(ink),
            style: StrokeStyle(lineWidth: s * 0.085, lineCap: .round, lineJoin: .round))
    }

    /// A drawn lemniscate — the ∞ glyph doesn't centre optically.
    static func infinity(in ctx: GraphicsContext, side s: CGFloat, ink: Color) {
        let r = s * 0.19
        var path = Path()
        path.addEllipse(in: CGRect(x: s * 0.30 - r, y: s * 0.5 - r, width: r * 2, height: r * 2))
        path.addEllipse(in: CGRect(x: s * 0.70 - r, y: s * 0.5 - r, width: r * 2, height: r * 2))
        ctx.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: s * 0.09))
    }

    static func stopwatch(
        in ctx: GraphicsContext, side s: CGFloat, at c: CGPoint? = nil, ink: Color
    ) {
        // Centre the face on the box; the crown pokes above.
        let center = c ?? CGPoint(x: s / 2, y: s * 0.50)
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

    static func coin(
        in ctx: GraphicsContext, side s: CGFloat, label text: String, ink: Color
    ) {
        let inset = s * 0.08
        let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
        ctx.stroke(
            Path(ellipseIn: rect), with: .color(ink), style: StrokeStyle(lineWidth: s * 0.08))
        label(text, in: ctx, side: s, ink: ink, scale: 0.42)
    }

    static func mine(in ctx: GraphicsContext, side s: CGFloat, ink: Color) {
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

    static func circleFace(in ctx: GraphicsContext, side s: CGFloat, ink: Color) {
        let inset = s * 0.10
        let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
        ctx.stroke(
            Path(ellipseIn: rect), with: .color(ink), style: StrokeStyle(lineWidth: s * 0.07))
    }

    /// The classic Minesweeper reset-button smiley — the face of "The Classics".
    static func smiley(in ctx: GraphicsContext, side s: CGFloat, ink: Color) {
        let inset = s * 0.10
        let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
        let c = CGPoint(x: s / 2, y: s / 2)
        ctx.stroke(
            Path(ellipseIn: rect), with: .color(ink), style: StrokeStyle(lineWidth: s * 0.07))
        // Two dot eyes.
        let eyeR = s * 0.05
        for dx in [-s * 0.15, s * 0.15] {
            let e = CGPoint(x: c.x + dx, y: c.y - s * 0.08)
            ctx.fill(
                Path(
                    ellipseIn: CGRect(
                        x: e.x - eyeR, y: e.y - eyeR, width: eyeR * 2, height: eyeR * 2)),
                with: .color(ink))
        }
        // An upturned smile arc.
        var mouth = Path()
        let mr = s * 0.20
        mouth.addArc(
            center: CGPoint(x: c.x, y: c.y + s * 0.02), radius: mr,
            startAngle: .degrees(25), endAngle: .degrees(155), clockwise: false)
        ctx.stroke(
            mouth, with: .color(ink), style: StrokeStyle(lineWidth: s * 0.06, lineCap: .round))
    }

    static func label(
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
