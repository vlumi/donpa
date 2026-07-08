#if os(macOS)
import AppKit
import SwiftUI

/// Invisible AppKit view that takes first responder and forwards arrow / Return /
/// Escape presses. Used by overlays because `@FocusState` can't reliably take it
/// from the SpriteKit board, especially after a game ends.
struct KeyCatcher: NSViewRepresentable {
    /// Arrow / Return / Escape, plus ⌘1–⌘4 (the New Game popup picks the board
    /// family by number — families are a list, not something to arrow through).
    enum Key { case up, down, left, right, enter, escape, family(Int) }
    let onKey: (Key) -> Void

    func makeNSView(context: Context) -> KeyCatcherView {
        let v = KeyCatcherView()
        v.onKey = onKey
        return v
    }

    func updateNSView(_ view: KeyCatcherView, context: Context) {
        view.onKey = onKey
        view.claimFocus()
    }

    final class KeyCatcherView: NSView {
        var onKey: ((Key) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            claimFocus()
        }

        /// Re-take first responder, deferred so it wins after the board/panel.
        func claimFocus() {
            guard let window else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window === window else { return }
                window.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            let key: Key?
            switch event.keyCode {
            case 126: key = .up
            case 125: key = .down
            case 123: key = .left
            case 124: key = .right
            case 36, 76: key = .enter  // Return, keypad Enter
            case 53: key = .escape
            default: key = nil
            }
            if let key {
                onKey?(key)
            } else {
                super.keyDown(with: event)
            }
        }

        /// ⌘1…⌘4 pick the board family. These arrive as key equivalents
        /// (⌘-combos don't come through `keyDown`), so handle them here.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                let n = Int(event.charactersIgnoringModifiers ?? ""), (1...4).contains(n)
            else {
                return super.performKeyEquivalent(with: event)
            }
            onKey?(.family(n))
            return true
        }
    }
}
#endif
