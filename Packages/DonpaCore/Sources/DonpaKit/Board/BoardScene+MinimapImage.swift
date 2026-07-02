import DonpaCore
import SpriteKit

/// The minimap's overview raster: the whole board downsampled to one small image
/// (a `ppc`×`ppc` block per cell), rendered off the main thread with cancellation
/// so a burst of revisions on a huge board can't pile up renders. The layout /
/// interaction half of the minimap lives in BoardScene+Minimap.
extension BoardScene {
    /// Render the whole board to a small image for the minimap sprite.
    func updateMinimapImage(boardW: Int, boardH: Int) {
        // Pixels-per-cell, capped so a 1024² board still renders to a sane bitmap.
        let maxDim = 240
        let ppc = max(1, min(maxDim / max(boardW, boardH), 4))
        // Render OFF the main thread (the per-cell loop is heavy on a 1M-cell
        // board): snapshot the Sendable board + colours now, apply the texture back
        // on the main actor only if no newer board state has superseded it.
        let board = viewModel.game.board
        let colors = overviewColors
        let generation = lastMinimapRevision
        // Supersede any render still running for an older revision — its result
        // would be discarded anyway, so don't let it finish burning a core.
        // Cancellation reaches the body through the stored handle (`.cancel()` sets
        // THAT task's flag, which `Task.isCancelled` inside `renderOverview` reads);
        // detached only means it doesn't inherit the MainActor context — wanted.
        minimapRenderTask?.cancel()
        minimapRenderTask = Task.detached { [weak self] in
            let cg = Self.renderOverview(
                board: board, width: boardW, height: boardH, ppc: ppc, colors: colors)
            guard let cg else { return }
            await MainActor.run {
                guard let self, !Task.isCancelled,
                    generation == self.lastMinimapRevision
                else { return }
                let texture = SKTexture(cgImage: cg)
                texture.filteringMode = .nearest  // crisp cell blocks, no blur
                self.minimapImage?.texture = texture
            }
        }
    }

    /// Overview fill colours, bundled `Sendable` so the render can run off the main
    /// actor (it can't touch `palette` there).
    struct OverviewColors: Sendable {
        let hidden, revealed, mine, flag: CGColor
    }
    var overviewColors: OverviewColors {
        OverviewColors(
            hidden: palette.hiddenTile.cgColor, revealed: palette.revealedTile.cgColor,
            mine: palette.mineTile.cgColor, flag: palette.flagGlyph.cgColor)
    }

    /// Pure renderer — no `self`, so it runs on any thread. Inputs are `Sendable`.
    /// Draws one `ppc`×`ppc` block per cell (hidden/revealed/mine/flag distinct);
    /// board row 0 paints at CG y=0 (what the viewport-rect math expects).
    nonisolated static func renderOverview(
        board: Board, width boardW: Int, height boardH: Int, ppc: Int, colors: OverviewColors
    ) -> CGImage? {
        let pxW = boardW * ppc
        let pxH = boardH * ppc
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard
            let ctx = CGContext(
                data: nil, width: pxW, height: pxH, bitsPerComponent: 8, bytesPerRow: 0,
                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        ctx.setFillColor(colors.hidden)
        ctx.fill(CGRect(x: 0, y: 0, width: pxW, height: pxH))
        // Walk the dense flat store by index — NOT `board[Coord(x,y)]`, which does a
        // topology `index(of:)` + protocol-witness dispatch + ARC retain/release per
        // cell. On a 1M-cell board that per-cell overhead WAS the runaway (profiled
        // ~74% of all CPU in `Board.subscript`/`swift_retain`). Index → x,y directly.
        var aborted = false
        board.forEachCellIndexed { i, cell in
            if aborted { return }
            // Cancellation: a newer board revision supersedes this render. Check only
            // periodically — `Task.isCancelled` per cell would itself be 1M calls.
            if i & 0x3FFF == 0, Task.isCancelled {
                aborted = true
                return
            }
            let color: CGColor?
            switch cell.state {
            case .revealed: color = cell.isMine ? colors.mine : colors.revealed
            case .flagged: color = colors.flag
            case .hidden: color = nil  // background already painted
            }
            guard let color else { return }
            let x = i % boardW
            let y = i / boardW
            ctx.setFillColor(color)
            ctx.fill(CGRect(x: x * ppc, y: y * ppc, width: ppc, height: ppc))
        }
        if aborted { return nil }
        return ctx.makeImage()
    }
}
