#if os(macOS)
import AppKit
import SwiftUI

/// Invisible AppKit view that takes first responder and forwards the keyboard
/// vocabulary: arrows, Return, Esc, Space, Tab/⇧Tab, plain letters, and ⌘1–⌘4.
/// Used by overlays because `@FocusState` can't reliably take focus from the
/// SpriteKit board, especially after a game ends. One catcher per window — two
/// would fight over first responder (both re-claim on every SwiftUI update).
struct KeyCatcher: NSViewRepresentable {
    /// Arrow / Return / Escape, plus ⌘1–⌘4 (the New Game popup picks the board
    /// family by number — families are a list, not something to arrow through)
    /// and plain letter keys (surface-specific actions, e.g. the Record's play).
    enum Key: Equatable {
        case up, down, left, right, enter, escape, space
        case tab, backTab
        case family(Int)
        case character(Character)
        /// A mouse-down anywhere in the window (never consumed) — hosts clear
        /// their keyboard focus ring so it can't linger under mouse use; a
        /// control that takes focus on click sets it again on mouse-up.
        case click
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
        private var fieldMonitor: Any?
        private var mouseMonitor: Any?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let fieldMonitor {
                NSEvent.removeMonitor(fieldMonitor)
                self.fieldMonitor = nil
            }
            if let mouseMonitor {
                NSEvent.removeMonitor(mouseMonitor)
                self.mouseMonitor = nil
            }
            guard window != nil else { return }
            claimFocus()
            if yieldsToTextFields { installFieldMonitor() }
            installMouseMonitor()
        }

        deinit {
            if let fieldMonitor { NSEvent.removeMonitor(fieldMonitor) }
            if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        }

        /// Any mouse-down in our window clears the host's focus ring (`.click`
        /// is informational — the event always passes through untouched).
        private func installMouseMonitor() {
            guard mouseMonitor == nil else { return }
            mouseMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] event in
                if let self, event.window === self.window { self.onKey?(.click) }
                return event
            }
        }

        /// While a field editor is typing, Tab and Esc must stay NAVIGATION:
        /// Tab ends the edit and moves on in one press (not the field
        /// editor's own multi-stop key loop), Esc just ends the edit instead
        /// of falling through to the sheet's cancel. Everything else types.
        /// A local monitor, because the catcher isn't first responder while
        /// the field editor is — its `keyDown` never fires.
        private func installFieldMonitor() {
            guard fieldMonitor == nil else { return }
            fieldMonitor = NSEvent.addLocalMonitorForEvents(
                matching: .keyDown
            ) { [weak self] event in
                guard let self else { return event }
                return self.interceptFieldKey(event)
            }
        }

        private func interceptFieldKey(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window,
                window.firstResponder is NSTextView
            else { return event }
            switch event.keyCode {
            case 48:  // Tab / ⇧Tab
                window.makeFirstResponder(self)
                onKey?(event.modifierFlags.contains(.shift) ? .backTab : .tab)
                return nil
            case 53:  // Esc
                window.makeFirstResponder(self)
                return nil
            default:
                return event
            }
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
            } else if pageScroll(for: event) {
                // handled: Page Up/Down scrolled the enclosing scroll view
            } else {
                super.keyDown(with: event)
            }
        }

        /// Page Up/Down (a screenful) and Home/End (top/bottom) scroll the
        /// enclosing scroll view — because this view holds first responder,
        /// AppKit's default handling never reaches the SwiftUI ScrollView, so
        /// drive it directly. Lets the keyboard reveal content taller than the
        /// window (e.g. the Record's career block on a small window) without
        /// overloading the arrows.
        private func pageScroll(for event: NSEvent) -> Bool {
            let pageUp = 116, pageDown = 121, home = 115, end = 119
            let code = Int(event.keyCode)
            guard [pageUp, pageDown, home, end].contains(code),
                // The catcher is seated as a background SIBLING of the scroll
                // (not an ancestor), so `enclosingScrollView` is nil — find the
                // scroll view by walking the window's view tree instead.
                let scroll = enclosingScrollView
                    ?? window?.contentView.flatMap(Self.firstScrollView),
                let doc = scroll.documentView
            else { return false }
            let visible = scroll.contentView.bounds
            let step = visible.height * 0.85  // a screenful, minus overlap
            let maxY = max(0, doc.bounds.height - visible.height)
            let y: CGFloat
            switch code {
            case home: y = 0
            case end: y = maxY
            case pageDown: y = min(maxY, visible.origin.y + step)
            default: y = max(0, visible.origin.y - step)  // pageUp
            }
            scroll.contentView.scroll(to: NSPoint(x: visible.origin.x, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            return true
        }

        /// Depth-first search for the first scroll view under `view` — the
        /// sheet's single content scroll (the only one on these surfaces).
        private static func firstScrollView(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            for sub in view.subviews {
                if let found = firstScrollView(sub) { return found }
            }
            return nil
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
