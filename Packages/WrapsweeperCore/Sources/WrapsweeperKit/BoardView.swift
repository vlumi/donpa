import SpriteKit
import SwiftUI

/// Hosts a `BoardScene`. On iOS this is just `SpriteView`; on macOS it wraps a
/// custom `SKView` subclass so two-finger scroll (which `SKView` does not
/// forward to the scene's `scrollWheel`) reaches the scene for panning.
struct BoardView: View {
    let scene: BoardScene

    var body: some View {
        #if os(macOS)
        ScrollingSpriteView(scene: scene)
        #else
        SpriteView(scene: scene, options: [.ignoresSiblingOrder])
        #endif
    }
}

#if os(macOS)
private struct ScrollingSpriteView: NSViewRepresentable {
    let scene: BoardScene

    func makeNSView(context: Context) -> ScrollForwardingSKView {
        let view = ScrollForwardingSKView()
        view.ignoresSiblingOrder = true
        view.presentScene(scene)
        return view
    }

    func updateNSView(_ view: ScrollForwardingSKView, context: Context) {
        if view.scene !== scene { view.presentScene(scene) }
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
#endif
