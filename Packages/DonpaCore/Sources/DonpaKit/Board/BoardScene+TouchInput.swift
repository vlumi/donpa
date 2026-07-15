#if os(iOS)
import DonpaCore
import SpriteKit
import UIKit

/// Touch input: the tap/long-press/pinch recognizers over the shared
/// action routing in BoardScene+Input.
extension BoardScene {
    @objc func handlePan(_ g: UIPanGestureRecognizer) {
        let sp = scenePoint(fromViewPoint: g.location(in: g.view))
        // Classify the drag at .began and hold the mode for the whole gesture (so a
        // fast drag off the map stays what it started as): handle → resize, else
        // map interior → scrub, else board → pan.
        if g.state == .began {
            resizingMinimap = minimapHandleHit(atScenePoint: sp)
            scrubbingMinimap = !resizingMinimap && handleMinimapNavigation(atScenePoint: sp)
            lastPan = .zero
        }
        let ending = g.state == .ended || g.state == .cancelled
        if resizingMinimap {
            resizeMinimap(toScenePoint: sp)
            if ending { resizingMinimap = false }
            return
        }
        if scrubbingMinimap {
            scrubMinimap(toScenePoint: sp)  // clamps, so dragging off-edge pins to it
            if ending { scrubbingMinimap = false }
            return
        }
        let t = g.translation(in: g.view)
        pan(byTranslation: CGPoint(x: t.x - lastPan.x, y: t.y - lastPan.y))
        lastPan = t
        if ending { panEnded() }
    }

    @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
        // Zoom toward the pinch midpoint so the point under the fingers stays put.
        zoom(by: g.scale, aroundViewPoint: g.location(in: g.view))
        g.scale = 1
    }

    @objc func handleTap(_ g: UITapGestureRecognizer) {
        tapAction(atScenePoint: scenePoint(fromViewPoint: g.location(in: g.view)))
    }

    @objc func handleLong(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        longPressAction(atScenePoint: scenePoint(fromViewPoint: g.location(in: g.view)))
    }
}
#endif
