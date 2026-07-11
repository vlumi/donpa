import DonpaCore
import SpriteKit
import SwiftUI

/// Hosts a `BoardScene` and keeps its palette in sync. The palette is passed as a
/// value so `update{NS,UI}View` pushes it to the scene on every resolved-scheme
/// change — deterministic, unlike `.onChange` (unreliable for the SpriteKit scene).
struct BoardView: View {
    let scene: BoardScene
    let palette: Palette
    let inputMode: InputMode
    /// When false (e.g. result panel up), show the normal arrow, not the mode cursor.
    var boardCursorActive: Bool = true
    var showMinimap: Bool = true
    var minimapScale: Double = 1
    var useQuestionMarks: Bool = false

    var body: some View {
        BoardSKView(
            scene: scene, palette: palette, inputMode: inputMode,
            boardCursorActive: boardCursorActive, showMinimap: showMinimap,
            minimapScale: minimapScale, useQuestionMarks: useQuestionMarks)
    }
}

#if os(macOS)
private struct BoardSKView: NSViewRepresentable {
    let scene: BoardScene
    let palette: Palette
    let inputMode: InputMode
    let boardCursorActive: Bool
    let showMinimap: Bool
    let minimapScale: Double
    let useQuestionMarks: Bool

    func makeNSView(context: Context) -> ScrollForwardingSKView {
        let view = ScrollForwardingSKView()
        view.ignoresSiblingOrder = true
        scene.palette = palette
        scene.showMinimap = showMinimap
        scene.minimapScale = CGFloat(minimapScale)
        scene.useQuestionMarks = useQuestionMarks
        view.inputMode = inputMode
        view.boardCursorActive = boardCursorActive
        view.presentScene(scene)
        return view
    }

    func updateNSView(_ view: ScrollForwardingSKView, context: Context) {
        if view.scene !== scene { view.presentScene(scene) }
        scene.palette = palette
        scene.showMinimap = showMinimap
        scene.minimapScale = CGFloat(minimapScale)
        scene.useQuestionMarks = useQuestionMarks
        view.inputMode = inputMode
        view.boardCursorActive = boardCursorActive
        // While the board is the live surface, keep it first responder so the
        // cursor keys land here: SwiftUI buttons keep focus after popups/sheets
        // close, leaving arrows dead and Return firing a stray default action.
        // Inactive states (title, pause, popups — boardCursorActive false) leave
        // focus alone, so this never fights the New Game popup's KeyCatcher; the
        // deferred claim mirrors KeyCatcher's own (win after the dismissal).
        if boardCursorActive, view.window?.firstResponder !== view {
            DispatchQueue.main.async { [weak view] in
                guard let view, let window = view.window else { return }
                if window.firstResponder !== view { window.makeFirstResponder(view) }
            }
        }
    }
}

/// An `SKView` that forwards `scrollWheel` to its scene (it otherwise swallows it)
/// and shows a mode-aware cursor over the board.
final class ScrollForwardingSKView: SKView {
    var inputMode: InputMode = .reveal {
        didSet {
            guard inputMode != oldValue else { return }
            refreshCursor()
        }
    }
    /// When false (result panel up), show the normal arrow over the board.
    var boardCursorActive: Bool = true {
        didSet {
            guard boardCursorActive != oldValue else { return }
            refreshCursor()
            // Becoming the live surface: one more claim AFTER the transition
            // settles (Home fade, SwiftUI focus engine) — a commit-time claim
            // alone can be re-overridden by a late focus re-assertion.
            if boardCursorActive {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                    self?.reclaimIfActive()
                }
            }
        }
    }

    private var pointerInside = false
    private var keyWindowObserver: Any?

    // Closing a macOS sheet RESTORES the parent window's pre-sheet first
    // responder, silently overriding the claim updateNSView made when the
    // game resumed — continuing from the in-progress sheet left the arrows
    // dead. Reclaim (deferred, to land after the restoration) whenever the
    // window becomes key while the board is the live surface.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyWindowObserver {
            NotificationCenter.default.removeObserver(keyWindowObserver)
            self.keyWindowObserver = nil
        }
        guard let window else { return }
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.reclaimIfActive() }
        }
    }

    deinit {
        if let keyWindowObserver { NotificationCenter.default.removeObserver(keyWindowObserver) }
    }

    private func reclaimIfActive() {
        guard boardCursorActive, let window, window.firstResponder !== self else { return }
        window.makeFirstResponder(self)
    }

    // Tracking area + explicit `NSCursor.set()` rather than `addCursorRect`: cursor
    // rects proved unreliable in the SwiftUI-hosted scene (the custom cursor never
    // showed); `mouseEntered`/`mouseMoved` + `set()` are immune to that timing.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
                owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        pointerInside = true
        cursor(for: effectiveMode).set()
    }

    override func mouseMoved(with event: NSEvent) {
        // Re-assert each move: AppKit otherwise resets to the arrow as the pointer
        // travels, and a sibling view's stale cursor can win.
        cursor(for: effectiveMode).set()
    }

    override func mouseExited(with event: NSEvent) {
        pointerInside = false
        NSCursor.arrow.set()
    }

    // Holding Control temporarily flips the action; reflect it in the cursor.
    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        refreshCursor()
    }

    /// The mode the next plain click would use: `inputMode`, flipped while Control
    /// is held (the temporary "other action" modifier).
    private var effectiveMode: InputMode {
        NSEvent.modifierFlags.contains(.control) ? inputMode.flipped : inputMode
    }

    /// Re-apply the cursor for the current mode/state if the pointer is over us.
    private func refreshCursor() {
        guard pointerInside else { return }
        cursor(for: effectiveMode).set()
    }

    private func cursor(for mode: InputMode) -> NSCursor {
        guard boardCursorActive else { return .arrow }
        switch mode {
        case .reveal: return .pointingHand
        case .flag: return Self.flagCursor
        }
    }

    /// A flag cursor from the `flag.fill` SF Symbol, tinted orange to match the
    /// flag-mode toggle. SF Symbols stay crisp at cursor size.
    private static let flagCursor: NSCursor = {
        let size = NSSize(width: 24, height: 24)
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        let symbol =
            NSImage(systemSymbolName: "flag.fill", accessibilityDescription: "Flag")?
            .withSymbolConfiguration(config)
        guard let symbol else { return .arrow }
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.systemOrange.set()
            rect.fill(using: .sourceOver)
            symbol.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
        // Hot spot at the flagpole base.
        return NSCursor(image: image, hotSpot: NSPoint(x: 4, y: size.height - 4))
    }()

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
    let inputMode: InputMode  // unused on iOS (no pointer cursor)
    let boardCursorActive: Bool  // gates the hardware-keyboard focus claim
    let showMinimap: Bool
    let minimapScale: Double
    let useQuestionMarks: Bool

    func makeUIView(context: Context) -> KeyForwardingSKView {
        let view = KeyForwardingSKView()
        view.ignoresSiblingOrder = true
        scene.palette = palette
        scene.showMinimap = showMinimap
        scene.minimapScale = CGFloat(minimapScale)
        scene.useQuestionMarks = useQuestionMarks
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ view: KeyForwardingSKView, context: Context) {
        if view.scene !== scene { view.presentScene(scene) }
        scene.palette = palette
        scene.showMinimap = showMinimap
        scene.minimapScale = CGFloat(minimapScale)
        scene.useQuestionMarks = useQuestionMarks
        // While the board is the live surface, hold first responder so a
        // hardware keyboard (iPad) drives the cursor. boardCursorActive is
        // false whenever a modal is up, so a sheet's text field is never
        // robbed of its keyboard.
        if boardCursorActive, !view.isFirstResponder, view.window != nil {
            DispatchQueue.main.async { [weak view] in
                guard let view, view.window != nil, !view.isFirstResponder else { return }
                view.becomeFirstResponder()
            }
        }
    }
}

/// An `SKView` that maps hardware-keyboard presses (iPad, or a paired keyboard
/// on iPhone) onto the same cursor entry points the Mac's keyDown drives.
final class KeyForwardingSKView: SKView {
    override var canBecomeFirstResponder: Bool { true }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let board = scene as? BoardScene else {
            return super.pressesBegan(presses, with: event)
        }
        var handled = false
        for press in presses {
            guard let key = press.key else { continue }
            handled = handle(key.keyCode, on: board) || handled
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }

    private func handle(_ code: UIKeyboardHIDUsage, on board: BoardScene) -> Bool {
        if let (dx, dy) = Self.arrowVector(code) {
            board.moveCursor(dx: dx, dy: dy)
            return true
        }
        switch code {
        case .keyboardReturnOrEnter, .keypadEnter: board.activateCursor()
        case .keyboardF: board.flagCursor()
        case .keyboardSpacebar: board.viewModel.inputMode.toggle()
        case .keyboardEscape:
            if board.viewModel.isPaused {
                board.viewModel.resume()
            } else {
                board.viewModel.pause()
            }
        default: return false
        }
        return true
    }

    /// Arrow → cursor step; rows render bottom-up, so up = +y.
    private static func arrowVector(_ code: UIKeyboardHIDUsage) -> (Int, Int)? {
        switch code {
        case .keyboardUpArrow: return (0, 1)
        case .keyboardDownArrow: return (0, -1)
        case .keyboardLeftArrow: return (-1, 0)
        case .keyboardRightArrow: return (1, 0)
        default: return nil
        }
    }
}
#endif
