import DonpaCore
import SpriteKit

/// The focused-cell cursor: one keyboard/VoiceOver-navigable cell, marked by an
/// ink ring over the tile. The scene owns the cursor's SCREEN coordinate (so on
/// a wrapped board it walks across the seam like a pan does); the logical cell
/// it focuses is mirrored to `viewModel.focusedCell` for the chrome. Arrow keys
/// move it, the primary key acts on it (BoardScene+Input routes the keys here).
extension BoardScene {
    /// True while cursor input is meaningful: a live, unpaused game.
    private var cursorLive: Bool {
        !viewModel.isPaused
            && (viewModel.status == .notStarted || viewModel.status == .playing)
    }

    /// Move the cursor one cell; the first move seeds it at the viewport centre.
    /// `dx`/`dy` are in VISUAL terms — rows render bottom-up (world y grows with
    /// the row index), so the up arrow passes dy = +1.
    func moveCursor(dx: Int, dy: Int) {
        guard cursorLive else { return }
        if let current = cursorScreenCoord {
            if isWrapped {
                // Screen space tiles infinitely; the logical cell folds via
                // `displayCoord`, so the cursor crosses the seam like a drag pans.
                cursorScreenCoord = Coord(current.x + dx, current.y + dy)
            } else if let stepped = viewModel.game.board.topology.stepped(
                current, dx: dx, dy: dy)
            {
                cursorScreenCoord = stepped
            }  // bounded edge: stay put
        } else {
            seedCursor()
        }
        syncFocusAndCamera()
        // Render the move NOW — at the idle frame rate it lags a beat behind
        // the key (the throttle only lifts on the next frame).
        view?.preferredFramesPerSecond = 60
    }

    /// The primary action on the focused cell — exactly a tap's routing
    /// (revealed chords; hidden follows the input mode).
    func activateCursor() {
        guard cursorLive, let screen = cursorScreenCoord else { return }
        perform(primaryActionAt: displayCoord(screen))
    }

    /// Toggle a flag (or "?") on the focused cell, regardless of input mode.
    func flagCursor() {
        guard cursorLive, let screen = cursorScreenCoord else { return }
        toggleFlagWithSound(displayCoord(screen))
    }

    /// First arrow press: land in the middle of what's on screen.
    private func seedCursor() {
        let r = visibleRange()
        let mid = Coord((r.minX + r.maxX) / 2, (r.minY + r.maxY) / 2)
        cursorScreenCoord =
            isWrapped ? mid : viewModel.game.board.topology.normalize(mid) ?? Coord(0, 0)
    }

    /// Mirror the logical cell to the VM and keep the cursor on-screen: when it
    /// steps out of the viewport, centre the camera on it (folding a wrapped
    /// cursor back onto the base board first — the camera clamps there).
    private func syncFocusAndCamera() {
        guard var screen = cursorScreenCoord else {
            viewModel.focusedCell = nil
            return
        }
        if !visibleRange().contains(screen) {
            if isWrapped {
                screen = displayCoord(screen)
                cursorScreenCoord = screen
            }
            cameraNode.position = clampedCameraPosition(layout.center(of: screen))
        }
        viewModel.focusedCell = displayCoord(screen)
    }

    /// A click/tap moves an ACTIVE cursor to the acted-on cell, so the arrows
    /// resume from where the mouse left off and the ring never lingers where
    /// the keyboard last was. A dormant cursor stays dormant — mouse-only
    /// play never summons the ring.
    func syncCursorToPointer(atScenePoint p: CGPoint) {
        guard cursorScreenCoord != nil, let screen = screenCoord(atScenePoint: p) else { return }
        cursorScreenCoord = screen
        viewModel.focusedCell = displayCoord(screen)
        view?.preferredFramesPerSecond = 60
    }

    /// The SCREEN-space cell under a scene point (unfolded on wrapped boards —
    /// the cursor's coordinate space), or nil off a bounded board.
    private func screenCoord(atScenePoint p: CGPoint) -> Coord? {
        guard viewModel.game.board.cellCount > 0 else { return nil }
        let local = boardLayer.convert(p, from: self)
        if isWrapped { return layout.unclampedCoord(at: local) }
        return layout.coord(at: local)
    }

    /// Reset on a new game (the `gameID` branch of `rebuildIfNeeded`): the board
    /// geometry changed under the cursor. The VM clears `focusedCell` itself.
    func resetCursor() {
        cursorScreenCoord = nil
        cursorNode?.isHidden = true
    }

    /// Per-frame: position/show the single ring node (one node — cheap).
    func refreshCursor() {
        guard let screen = cursorScreenCoord, cursorLive else {
            cursorNode?.isHidden = true
            return
        }
        let node: SKSpriteNode
        if let existing = cursorNode {
            node = existing
        } else {
            node = SKSpriteNode()
            cursorLayer.addChild(node)
            cursorNode = node
        }
        node.isHidden = false
        node.texture = cursorRingTexture()
        node.size = layout.tileSize
        node.position = layout.center(of: screen)
    }

    /// Tile-outline ring (square or hex per layout), cached like the other tile
    /// textures. Full-strength glyph ink (white on dark, near-black on light —
    /// the screentone wash ink was invisible on dark tiles) and thicker than
    /// the over-flag ring, so "you are here" reads without relying on colour.
    private func cursorRingTexture() -> SKTexture {
        let shape = layout.tileShape
        let (wPx, hPx) = tilePixelSize()
        let color = palette.mineGlyph
        let key = "cursor-\(shape)-\(wPx)x\(hPx)-\(color)"
        if let cached = tileTextureCache[key] { return cached }

        let scale: CGFloat = 2
        let lineWidth = max(3, CGFloat(wPx) * scale * 0.1)
        let img = drawTileImage(wPx: wPx, hPx: hPx, scale: scale) { ctx, w, h in
            addTilePath(to: ctx, shape: shape, w: w, h: h, inset: lineWidth / 2)
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(lineWidth)
            ctx.strokePath()
        }
        let texture = SKTexture(cgImage: img)
        texture.filteringMode = .linear
        tileTextureCache[key] = texture
        return texture
    }
}
