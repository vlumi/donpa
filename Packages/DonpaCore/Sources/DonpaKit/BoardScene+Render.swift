import DonpaCore
import SpriteKit

/// Board rendering: cell-node construction and **viewport culling**. Only cells
/// within the camera's visible rect are built (kept in `cellNodes`), so the live
/// node count stays ~one screenful regardless of board size — the path that makes
/// huge boards (e.g. 100×100) tractable. Split out of BoardScene.swift to keep
/// that file within length limits.
extension BoardScene {
    func rebuildIfNeeded() {
        if viewModel.gameID != lastGameID {
            lastGameID = viewModel.gameID
            lastAnimatedResultID = -1  // a fresh game can animate its own result
            effectsLayer.removeAllChildren()
            boardLayer.position = .zero  // clear any leftover shake offset
            centerCamera()
        }
        if viewModel.revision != lastRevision {
            lastRevision = viewModel.revision
            rebuild()
        }
        // After the board reflects the final state, play the end-game effect
        // once. No further revisions occur post-end, so this fires exactly once.
        if let event = viewModel.lastResult, event.id != lastAnimatedResultID {
            lastAnimatedResultID = event.id
            playEndGameEffects(event.result)
        }
    }

    /// An inclusive rectangular range of cell coordinates (the visible window).
    /// Internal so the +Effects extension can cull the mode-glow to the same range.
    struct CellRange: Equatable {
        let minX, maxX, minY, maxY: Int
        func contains(_ c: Coord) -> Bool {
            c.x >= minX && c.x <= maxX && c.y >= minY && c.y <= maxY
        }
        /// Visit every coordinate in the range (row-major).
        func forEach(_ body: (Coord) -> Void) {
            guard minX <= maxX, minY <= maxY else { return }
            for y in minY...maxY {
                for x in minX...maxX { body(Coord(x, y)) }
            }
        }
    }

    /// The cells currently within the camera's viewport, plus a one-cell margin so
    /// a cell is built just before it scrolls in. Clamped to the board bounds, so
    /// for a board that fits the viewport this is the whole board (culling no-op).
    func visibleRange() -> CellRange {
        let w = viewModel.boardWidth
        let h = viewModel.boardHeight
        let scale = cameraNode.xScale
        // Visible world half-extents: scene is `size` points, scaled by the camera.
        let halfW = size.width / 2 * scale
        let halfH = size.height / 2 * scale
        let cam = cameraNode.position
        let cell = layout.cellSize
        // World rect → cell indices (SquareLayout: cell = floor(world / cellSize)).
        // +1 cell of margin each side so cells appear before scrolling fully in.
        let minX = max(0, Int(((cam.x - halfW) / cell).rounded(.down)) - 1)
        let maxX = min(w - 1, Int(((cam.x + halfW) / cell).rounded(.down)) + 1)
        let minY = max(0, Int(((cam.y - halfH) / cell).rounded(.down)) - 1)
        let maxY = min(h - 1, Int(((cam.y + halfH) / cell).rounded(.down)) + 1)
        return CellRange(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }

    /// Full rebuild: drop all cell nodes and rebuild those in the visible range.
    /// Called on a board-state change (`revision`) or palette change.
    func rebuild() {
        boardLayer.removeAllChildren()
        cellNodes.removeAll(keepingCapacity: true)
        builtRange = nil
        buildVisibleCells()
    }

    /// Bring the built cell nodes in line with the current visible range: add
    /// newly-visible cells, remove newly-hidden ones. O(visible), not O(board) —
    /// the core of culling. Idempotent, so it's safe to call on every viewport
    /// change (pan/zoom) and after a rebuild.
    func buildVisibleCells() {
        let range = visibleRange()
        guard range != builtRange else { return }
        let game = viewModel.game

        // Remove cells that have scrolled out of view.
        for (c, node) in cellNodes where !range.contains(c) {
            node.removeFromParent()
            cellNodes[c] = nil
        }
        // Add cells that have scrolled into view (skip any already built).
        for y in range.minY...range.maxY {
            for x in range.minX...range.maxX {
                let c = Coord(x, y)
                guard cellNodes[c] == nil else { continue }
                let node = cellNode(for: c, cell: game.board[c])
                node.position = layout.center(of: c)
                boardLayer.addChild(node)
                cellNodes[c] = node
            }
        }
        builtRange = range
    }

    private func cellNode(for coord: Coord, cell: Cell) -> SKNode {
        let size = layout.cellSize
        let container = SKNode()
        let inset: CGFloat = 1
        let rect = CGRect(
            x: -size / 2 + inset, y: -size / 2 + inset,
            width: size - inset * 2, height: size - inset * 2)
        let tile = SKShapeNode(rect: rect, cornerRadius: 3)
        tile.lineWidth = 0
        tile.fillColor = fillColor(for: cell)
        container.addChild(tile)

        // The mine you hit gets the manga burst (icon motif, flat); other mines
        // keep the plain ✸. Flagged cells get the swallowtail flag matching the
        // toolbar toggle (a SpriteKit-drawn glyph, not a text character).
        if cell.state == .revealed, cell.isMine, coord == viewModel.game.lossCoord {
            container.addChild(burstMineNode(size: size))
        } else if cell.state == .flagged {
            container.addChild(flagNode(size: size, color: palette.flagGlyph))
        } else if let glyph = glyph(for: cell) {
            let label = SKLabelNode(text: glyph.text)
            label.fontName = "Menlo-Bold"
            label.fontSize = size * 0.5
            label.fontColor = glyph.color
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            container.addChild(label)
        }
        return container
    }

    private func fillColor(for cell: Cell) -> SKColor {
        switch cell.state {
        case .hidden, .flagged:
            return palette.hiddenTile
        case .revealed:
            return cell.isMine ? palette.mineTile : palette.revealedTile
        }
    }

    private func glyph(for cell: Cell) -> (text: String, color: SKColor)? {
        switch cell.state {
        case .flagged:
            return nil  // drawn as a swallowtail flagNode, not a text glyph
        case .hidden:
            return nil
        case .revealed:
            if cell.isMine { return ("✸", palette.mineGlyph) }
            guard cell.adjacentMines > 0 else { return nil }
            return (String(cell.adjacentMines), palette.number(cell.adjacentMines))
        }
    }
}
