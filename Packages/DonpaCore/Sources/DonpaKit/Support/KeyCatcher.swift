#if os(macOS)
import AppKit
import SwiftUI

/// Invisible AppKit view that takes first responder and forwards arrow / Return /
/// Escape presses. Used by overlays because `@FocusState` can't reliably take it
/// from the SpriteKit board, especially after a game ends.
struct KeyCatcher: NSViewRepresentable {
    /// Arrow / Return / Escape, plus ⌘1–⌘4 (the New Game popup picks the board
    /// family by number — families are a list, not something to arrow through)
    /// and plain letter keys (surface-specific actions, e.g. the Record's play).
    enum Key: Equatable {
        case up, down, left, right, enter, escape, space
        case tab, backTab
        case family(Int)
        case character(Character)
    }
    let onKey: (Key) -> Void
    /// When true, never steal first responder from an active text field — for
    /// surfaces that mix list navigation with editable fields (the Mess hall's
    /// name fields). The default (false) claims aggressively, which is right
    /// for field-free overlays like the New Game popup.
    var yieldsToTextFields = false

    func makeNSView(context: Context) -> KeyCatcherView {
        let v = KeyCatcherView()
        v.onKey = onKey
        v.yieldsToTextFields = yieldsToTextFields
        return v
    }

    func updateNSView(_ view: KeyCatcherView, context: Context) {
        view.onKey = onKey
        view.yieldsToTextFields = yieldsToTextFields
        view.claimFocus()
    }

    final class KeyCatcherView: NSView {
        var onKey: ((Key) -> Void)?
        var yieldsToTextFields = false

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
                if self.yieldsToTextFields,
                    window.firstResponder is NSTextView  // a field editor is typing
                {
                    return
                }
                window.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            if let key = Self.key(for: event) {
                onKey?(key)
            } else {
                super.keyDown(with: event)
            }
        }

        private static func key(for event: NSEvent) -> Key? {
            switch event.keyCode {
            case 126: return .up
            case 125: return .down
            case 123: return .left
            case 124: return .right
            case 36, 76: return .enter  // Return, keypad Enter
            case 49: return .space  // toggles the focused control (Return confirms)
            case 53: return .escape
            case 48:  // Tab / ⇧Tab — "next"/"previous" for surfaces without FKA
                return event.modifierFlags.contains(.shift) ? .backTab : .tab
            default:
                // Plain letters only — modified combos stay key equivalents.
                guard
                    event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                        .subtracting(.shift).isEmpty,
                    let ch = event.charactersIgnoringModifiers?.lowercased().first,
                    ch.isLetter
                else { return nil }
                return .character(ch)
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
