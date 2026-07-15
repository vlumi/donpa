#if os(macOS)
import DonpaCore
import SpriteKit
import SwiftUI

struct BoardSKView: NSViewRepresentable {
    let scene: BoardScene
    let palette: Palette
    let inputMode: InputMode
    let boardCursorActive: Bool
    let keyboardOwner: Bool
    let minimap: MinimapPrefs
    let useQuestionMarks: Bool

    func makeNSView(context: Context) -> ScrollForwardingSKView {
        let view = ScrollForwardingSKView()
        view.ignoresSiblingOrder = true
        applyScene(scene, palette: palette, minimap: minimap, useQuestionMarks: useQuestionMarks)
        view.inputMode = inputMode
        view.boardCursorActive = boardCursorActive
        view.keyboardOwner = keyboardOwner
        view.presentScene(scene)
        return view
    }

    func updateNSView(_ view: ScrollForwardingSKView, context: Context) {
        if view.scene !== scene { view.presentScene(scene) }
        applyScene(scene, palette: palette, minimap: minimap, useQuestionMarks: useQuestionMarks)
        view.inputMode = inputMode
        view.boardCursorActive = boardCursorActive
        view.keyboardOwner = keyboardOwner
    }
}

/// Board first-responder policy (macOS): while active, any change of the
/// window's first responder away from the board is corrected one runloop turn
/// later. Event-driven — KVO on the window's `firstResponder` catches both a
/// closing sheet restoring its pre-sheet responder and SwiftUI's focus engine
/// re-asserting after a shortcut-activated button; `didBecomeKey` covers the
/// window becoming key with a stale responder. Contract: never active while a
/// same-window KeyCatcher surface is up (title, popups, modals), so claimants
/// can't fight.
final class BoardFocusKeeper {  // main-thread-only, like the AppKit it drives
    private weak var view: NSView?
    private var responderObservation: NSKeyValueObservation?
    private var keyObserver: NSObjectProtocol?

    var isActive = false {
        didSet {
            if isActive, isActive != oldValue { reclaimSoon() }
        }
    }

    init(view: NSView) { self.view = view }

    /// Call from `viewDidMoveToWindow` (both directions).
    func windowChanged(_ window: NSWindow?) {
        responderObservation = nil
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = nil
        guard let window else { return }
        responderObservation = window.observe(\.firstResponder) { [weak self] _, _ in
            DispatchQueue.main.async { self?.reclaim() }
        }
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.reclaim() }
        }
        if isActive { reclaimSoon() }
    }

    deinit {
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
    }

    /// Deferred one turn, to land after AppKit's own responder churn.
    private func reclaimSoon() {
        DispatchQueue.main.async { [weak self] in self?.reclaim() }
    }

    private func reclaim() {
        guard isActive, let view, let window = view.window,
            window.firstResponder !== view
        else { return }
        window.makeFirstResponder(view)  // KVO refires; the !== guard terminates it
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
        }
    }
    /// Keyboard ownership, delegated to the keeper (separate from the
    /// pointer cursor: the board keeps the keys while PAUSED so Esc resumes).
    var keyboardOwner = false {
        didSet { keeper.isActive = keyboardOwner }
    }

    private var pointerInside = false
    private lazy var keeper = BoardFocusKeeper(view: self)

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        keeper.windowChanged(window)
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
#endif
