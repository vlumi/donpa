import SpriteKit
import SwiftUI

/// Hosts a `BoardScene` and keeps its palette in sync. The palette is passed in
/// as a value, so SwiftUI's `update{NS,UI}View` runs whenever the resolved
/// scheme changes and pushes it to the scene — deterministic, unlike relying on
/// `.onChange` to fire (which proved unreliable for the SpriteKit scene,
/// notably when toggling the system appearance on iOS/iPadOS).
struct BoardView: View {
    let scene: BoardScene
    let palette: Palette

    var body: some View {
        #if os(macOS)
        BoardSKView(scene: scene, palette: palette)
        #else
        BoardSKView(scene: scene, palette: palette)
        #endif
    }
}

#if os(macOS)
private struct BoardSKView: NSViewRepresentable {
    let scene: BoardScene
    let palette: Palette

    func makeNSView(context: Context) -> ScrollForwardingSKView {
        let view = ScrollForwardingSKView()
        view.ignoresSiblingOrder = true
        scene.palette = palette
        view.presentScene(scene)
        return view
    }

    func updateNSView(_ view: ScrollForwardingSKView, context: Context) {
        if view.scene !== scene { view.presentScene(scene) }
        scene.palette = palette
    }
}

/// An `SKView` that forwards scroll events to its scene — `SKView` otherwise
/// swallows `scrollWheel` instead of routing it to `BoardScene`.
final class ScrollForwardingSKView: SKView {
    override func scrollWheel(with event: NSEvent) {
        if let board = scene as? BoardScene {
            board.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}
#else
private struct BoardSKView: UIViewRepresentable {
    let scene: BoardScene
    let palette: Palette

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.ignoresSiblingOrder = true
        scene.palette = palette
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {
        if view.scene !== scene { view.presentScene(scene) }
        scene.palette = palette
    }
}
#endif
