import DonpaCore
import SpriteKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// The input-mode wash over unopened tiles: screentone textures (dots = dig,
/// hatch = flag) drawn once per (mode, size, appearance) and stamped over the
/// visible range. Separate from the end-game effects in BoardScene+Effects.
extension BoardScene {
    /// A faint screentone over the unopened tiles signalling which tool a tap will
    /// use. The cue is the PATTERN, not colour (colour-blind safe): dig = Ben-Day
    /// dots, flag = diagonal hatch, both in one neutral ink. Rebuilt only on mode /
    /// revision / visibility / viewport change, not every frame.
    func refreshModeGlow() {
        // Persists after win/loss, frozen at the last mode. Hidden while paused
        // (the pause overlay blurs the board anyway).
        let visible = !viewModel.isPaused
        let mode = viewModel.inputMode
        let range = visibleRange()
        guard
            mode != lastGlowMode || visible != lastGlowLive
                || viewModel.revision != lastGlowRevision || range != lastGlowRange
        else { return }
        lastGlowMode = mode
        lastGlowLive = visible
        lastGlowRevision = viewModel.revision
        lastGlowRange = range
        glowLayer.removeAllChildren()
        guard visible else { return }

        let texture = screentoneTexture(for: mode)
        let size = layout.cellSize
        // The texture is clipped to the tile outline (hexagon or rounded square) and
        // drawn at the tile's aspect, so the sprite matches the tile beneath exactly —
        // the wash follows the hex edges instead of overhanging as a square block.
        let washSize = layout.tileSize
        // Each wash tile is an `SKSpriteNode` sharing the one cached screentone
        // texture — so SpriteKit batches them all into ~one draw call (a huge board
        // can have thousands of unopened tiles on screen). A per-cell `SKShapeNode`
        // here pegged the CPU: SpriteKit re-tessellates every shape's path every
        // frame, never batching, so thousands of them re-stroked at 60fps melted the
        // Mac (XXXL on a big resizable window). The faint pattern over the rounded
        // tile beneath reads fine as a square, so no per-tile rounded-rect needed.
        // Flagged tiles are unopened, so they get the screentone too; since the
        // glow layer sits above the board's flag glyph, re-stamp the flag on top.
        // Only the visible window (same cull as the tiles).
        range.forEach { c in
            // `c` is the screen position (drawn there); read state from the logical
            // cell it shows (identity when bounded, wrapped cell when not).
            let state = viewModel.game.board[displayCoord(c)].state
            // A "?" tile is unopened too, so it takes the screentone like a flag.
            guard state == .hidden || state == .flagged || state == .questioned else { return }
            let center = layout.center(of: c)
            let tile = SKSpriteNode(texture: texture, size: washSize)
            tile.position = center
            tile.isUserInteractionEnabled = false
            glowLayer.addChild(tile)
            // Re-stamp the mark above the wash: the view sets `ignoresSiblingOrder`,
            // so equal-z siblings draw in undefined order — without an explicit
            // higher z the screentone sprite can land on top and stripe/dot the mark.
            if state == .flagged {
                let flag = flagSprite(size: size, color: palette.flagGlyph)
                flag.position = center
                flag.zPosition = 1
                glowLayer.addChild(flag)
            } else if state == .questioned {
                let mark = SKSpriteNode(texture: glyphTexture("?", color: palette.flagGlyph))
                mark.size = CGSize(width: size, height: size)
                mark.position = center
                mark.zPosition = 1
                glowLayer.addChild(mark)
            }
        }
    }

    /// Cached screentone texture for a mode: dots for dig, hatch for flag, in a faint
    /// neutral ink, **clipped to the tile outline** so on a hex board the wash follows
    /// the hexagon instead of overhanging as a square block. Cached per mode + tile
    /// pixel size + shape + ink. Drawn on a canvas matching the tile's aspect (a hex
    /// is taller than wide) so the pattern isn't squashed.
    func screentoneTexture(for mode: InputMode) -> SKTexture {
        let shape = layout.tileShape
        let (wPx, hPx) = tilePixelSize()
        let ink = palette.screentoneInk
        // Key by shape + ink so square/hex and light/dark don't share a stale texture.
        let key = "\(mode)-\(wPx)x\(hPx)-\(shape)-\(ink)"
        if let cached = glowTextureCache[key] { return cached }

        let scale = 2  // supersample for crisp dots/lines, then SKTexture downscales
        let w = wPx * scale
        let h = hPx * scale
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        // Clip everything (pattern + compensation) to the tile outline, so the wash
        // stops at the hexagon's slanted edges rather than filling the sprite square.
        ctx.saveGState()
        addTilePath(to: ctx, shape: shape, w: CGFloat(w), h: CGFloat(h), inset: 0)
        ctx.clip()
        ctx.setFillColor(ink.cgColor)
        ctx.setStrokeColor(ink.cgColor)
        drawScreentonePattern(ctx, mode: mode, width: CGFloat(w), height: CGFloat(h))
        // The ink pushes brightness one way (lighter on dark, darker on light); lay
        // an opposite-sign wash of equal average underneath so a screentoned tile
        // averages back to the bare tile colour.
        guard let inked = ctx.makeImage() else {
            ctx.restoreGState()
            return SKTexture()
        }
        let coverage = meanAlpha(of: inked, width: w, height: h)
        let comp = compensatingTexture(
            inkWhite: inkWhite(ink), coverage: coverage, width: w, height: h)
        let full = CGRect(x: 0, y: 0, width: w, height: h)
        // Compensation first, then the ink on top — both under the same tile clip.
        ctx.clear(full)
        if let comp { ctx.draw(comp, in: full) }
        ctx.draw(inked, in: full)
        ctx.restoreGState()

        let texture = SKTexture(cgImage: ctx.makeImage()!)
        texture.filteringMode = .linear
        glowTextureCache[key] = texture
        return texture
    }

    /// Draw the mode's screentone into `ctx` (already set to the ink colour): dig =
    /// staggered dots that shrink toward the centre, flag = diagonal hatch that
    /// thickens toward the centre — opposite vignettes so the modes read distinct.
    /// Pattern scale keys off the width; the vignette centres on the tile.
    private func drawScreentonePattern(
        _ ctx: CGContext, mode: InputMode, width: CGFloat, height: CGFloat
    ) {
        let f = width
        let midX = width / 2, midY = height / 2
        let maxDist = hypot(midX, midY)  // centre→corner
        switch mode {
        case .reveal:
            let gap = f * 0.20, baseR = f * 0.055
            var row = 0
            var y = gap / 2
            while y < height + gap {
                let offset = row.isMultiple(of: 2) ? 0 : gap / 2
                var x = gap / 2 - gap + offset
                while x < width + gap {
                    let dist = hypot(x - midX, y - midY) / maxDist
                    let r = baseR * (0.55 + 0.45 * dist)  // smaller centre, fuller edges
                    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    x += gap
                }
                y += gap * 0.86
                row += 1
            }
        case .flag:
            let gap = f * 0.18
            var d = -height
            while d < width {
                let lineMid = d + height / 2
                let dist = abs(lineMid - midX) / midX
                ctx.setLineWidth(f * (0.075 - 0.045 * min(1, dist)))  // thicker centre
                ctx.move(to: CGPoint(x: d, y: 0))
                ctx.addLine(to: CGPoint(x: d + height, y: height))
                ctx.strokePath()
                d += gap
            }
        }
    }

    /// The ink's white value (0 = black ink, 1 = white ink).
    private func inkWhite(_ color: SKColor) -> CGFloat {
        var w: CGFloat = 0, a: CGFloat = 0
        #if os(macOS)
        (color.usingColorSpace(.genericGray) ?? color).getWhite(&w, alpha: &a)
        #else
        color.getWhite(&w, alpha: &a)
        #endif
        return w
    }

    /// Mean alpha (0…1) of a premultiplied-RGBA image — how much of the sprite the
    /// ink pattern covers on average (over the full `width×height` canvas, which for
    /// a hex includes the transparent corners outside the clipped tile).
    private func meanAlpha(of image: CGImage, width: Int, height: Int) -> CGFloat {
        let bpr = width * 4
        var buf = [UInt8](repeating: 0, count: bpr * height)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let c = CGContext(
            data: &buf, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bpr,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var total = 0
        for i in stride(from: 3, to: buf.count, by: 4) { total += Int(buf[i]) }
        return CGFloat(total) / CGFloat(width * height) / 255
    }

    /// A flat wash of the opposite luminance to the ink, at the alpha that cancels
    /// the ink's average brightness. nil when no compensation is needed. Drawn full-
    /// canvas; the caller clips it to the tile outline along with the ink.
    private func compensatingTexture(
        inkWhite: CGFloat, coverage: CGFloat, width: Int, height: Int
    ) -> CGImage? {
        guard coverage > 0.001 else { return nil }
        let opposite: CGFloat = inkWhite > 0.5 ? 0 : 1
        let alpha = min(1, coverage)  // equal-area, opposite colour → mean ≈ neutral
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let c = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(red: opposite, green: opposite, blue: opposite, alpha: alpha)
        c.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return c.makeImage()
    }
}
