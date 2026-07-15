#if os(macOS)
import DonpaCore
import SpriteKit
import AppKit

/// Mouse, trackpad, and keyboard input: click/drag classification (incl.
/// the Magic Mouse sloppy-click reclassification), scroll/zoom, and the
/// key-command routing — over the shared action routing in BoardScene+Input.
extension BoardScene {
    @objc func handlePinch(_ g: NSMagnificationGestureRecognizer) {
        // Zoom toward the trackpad pinch centroid so the point under it stays put.
        zoom(by: 1 + g.magnification, aroundViewPoint: g.location(in: g.view))
        g.magnification = 0
    }

    /// Two-finger trackpad swipe (or mouse wheel) pans; ⌘+scroll zooms toward the
    /// cursor (the mouse-zoom idiom). Coarse wheel line deltas are scaled up.
    public override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let dy = event.scrollingDeltaY
            guard dy != 0 else { return }
            let factor = 1 + max(-0.5, min(0.5, dy * 0.01))  // up = in, down = out
            zoom(by: factor, aroundViewPoint: viewPoint(of: event))
            return
        }
        let step: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        // Trace only the phase edges (a Magic Mouse surface brush mid-play shows up
        // here) — per-event logging would flood during momentum.
        if event.phase == .began {
            InputTrace.log("scroll began")
        } else if event.momentumPhase == .began {
            InputTrace.log("scroll momentum began")
        } else if event.phase == .ended || event.momentumPhase == .ended {
            InputTrace.log("scroll ended")
        }
        // Natural scroll: content follows the fingers. AppKit Y grows upward like
        // the scene, so pass deltas through directly.
        pan(
            byTranslation: CGPoint(
                x: event.scrollingDeltaX * step, y: event.scrollingDeltaY * step))
        if event.phase == .ended || event.momentumPhase == .ended { panEnded() }
    }

    /// An event's location in hosting-view coords (for cursor-anchored zoom).
    private func viewPoint(of event: NSEvent) -> CGPoint? {
        guard let view else { return nil }
        return view.convert(event.locationInWindow, from: nil)
    }

    public override func mouseDown(with event: NSEvent) {
        // clickCount rises 2, 3, 4… while rapid same-spot clicks stay inside
        // the system multi-click window (a ~1s pause resets it).
        InputTrace.log("mouseDown clicks=\(event.clickCount)")
        let p = view?.convert(event.locationInWindow, from: nil) ?? .zero
        lastDragViewPoint = p
        mouseDownViewPoint = p
        mouseDownTimestamp = event.timestamp
        didDragInScene = false
        let sp = scenePoint(fromViewPoint: p)
        // A press on the resize handle starts a resize drag (a click-without-drag
        // toggles min/max, handled in mouseUp). Else a press on the map recenters
        // and scrubs for the drag.
        resizingMinimap = minimapHandleHit(atScenePoint: sp)
        scrubbingMinimap = !resizingMinimap && handleMinimapNavigation(atScenePoint: sp)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let view = view else { return }
        let p = view.convert(event.locationInWindow, from: nil)
        if resizingMinimap {
            // Only resize once movement clears the threshold — else a click with a
            // hair of jitter would resize a touch AND swallow the tap-to-toggle.
            if !didDragInScene {
                let moved = hypot(p.x - mouseDownViewPoint.x, p.y - mouseDownViewPoint.y)
                guard moved > Self.dragThreshold else { return }
                didDragInScene = true
            }
            resizeMinimap(toScenePoint: scenePoint(fromViewPoint: p))
            lastDragViewPoint = p
            return
        }
        if scrubbingMinimap {
            scrubMinimap(toScenePoint: scenePoint(fromViewPoint: p))  // clamps off-edge
            lastDragViewPoint = p
            return
        }
        // Grab model: content follows the cursor. Use the camera-independent
        // view-space delta and let pan() scale it by zoom.
        // Only become a drag once movement clears the threshold.
        if !didDragInScene {
            let moved = hypot(p.x - mouseDownViewPoint.x, p.y - mouseDownViewPoint.y)
            guard moved > Self.dragThreshold else { return }
            didDragInScene = true
        }
        // pan() applies +Y to the camera; negate so content follows the cursor.
        pan(byTranslation: CGPoint(x: p.x - lastDragViewPoint.x, y: -(p.y - lastDragViewPoint.y)))
        lastDragViewPoint = p
    }

    public override func mouseUp(with event: NSEvent) {
        if resizingMinimap {
            resizingMinimap = false
            // If it actually dragged, it resized — done. If not (a click on the
            // caret), fall through to tapAction below, which toggles min/max.
            if didDragInScene { return }
        }
        if scrubbingMinimap {  // the whole drag was a minimap scrub; not a board click
            scrubbingMinimap = false
            return
        }
        if didDragInScene {
            panEnded()  // spring back if the drag overshot the edge
            // A drag can still be a sloppy CLICK: a Magic Mouse slides a few points
            // under its own click force, so during rapid play every click crossed
            // the drag threshold and was silently eaten as a micro-pan (see
            // `clickSlop`). Brief + net-travel within the slop → click after all;
            // a real pan (longer or farther) stays a pan.
            let up = view?.convert(event.locationInWindow, from: nil) ?? .zero
            let net = hypot(up.x - mouseDownViewPoint.x, up.y - mouseDownViewPoint.y)
            let duration = event.timestamp - mouseDownTimestamp
            let counts = Self.sloppyClickCountsAsClick(net: net, duration: duration)
            InputTrace.log(
                "mouseUp dragged net=\(String(format: "%.1f", net)) "
                    + "dur=\(String(format: "%.2f", duration)) → \(counts ? "click" : "pan")")
            guard counts else { return }
        }
        let p = event.location(in: self)
        // Control is the temporary "other action" modifier: it does the long-press
        // action (flag in Reveal mode, reveal in Flag mode).
        if NSEvent.modifierFlags.contains(.control) {
            longPressAction(atScenePoint: p)
        } else {
            tapAction(atScenePoint: p)
        }
    }

    public override func rightMouseUp(with event: NSEvent) {
        // Right-click == Control-click == long-press: the OPPOSITE of the current
        // mode's primary action. So the dig/flag toggle assigns the two buttons —
        // Dig mode gives left-dig / right-flag (Windows-classic), Flag mode swaps
        // them — and both buttons always work, no toggling mid-play. On a revealed
        // number it chords, like the left button.
        longPressAction(atScenePoint: event.location(in: self))
    }

    // Key input handled directly: SwiftUI menu shortcuts for bare keys don't
    // fire reliably, but the scene receives key events via the responder
    // chain. The raw map translates to BoardKeyCommand, shared with the iPad
    // key forwarder.
    public override func keyDown(with event: NSEvent) {
        guard let command = Self.command(for: event) else {
            return super.keyDown(with: event)
        }
        // Keyboard play hides the pointer (it reappears on the next mouse
        // move) — the ring is doing the pointing now.
        NSCursor.setHiddenUntilMouseMoves(true)
        perform(command)
    }

    private static func command(for event: NSEvent) -> BoardKeyCommand? {
        switch event.keyCode {
        case 49: return .toggleMode  // Space
        case 53: return .pauseResume  // Esc
        case 123: return .move(dx: -1, dy: 0)  // ←
        case 124: return .move(dx: 1, dy: 0)  // →
        case 125: return .move(dx: 0, dy: -1)  // ↓ (rows render bottom-up)
        case 126: return .move(dx: 0, dy: 1)  // ↑
        case 36, 76: return .activate  // Return / keypad Enter
        case 3: return .flag  // F
        default: return BoardKeyCommand.wasd(event.charactersIgnoringModifiers)
        }
    }
}
#endif
