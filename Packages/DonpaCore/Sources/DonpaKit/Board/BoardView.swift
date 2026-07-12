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
    /// Whether the board owns the hardware keyboard: the live surface,
    /// INCLUDING paused (Esc must always reach the scene to resume), but never
    /// under the title or a modal — that's the no-fight contract with the
    /// KeyCatcher surfaces.
    var keyboardOwner: Bool = true
    var showMinimap: Bool = true
    var minimapScale: Double = 1
    var useQuestionMarks: Bool = false

    var body: some View {
        BoardSKView(
            scene: scene, palette: palette, inputMode: inputMode,
            boardCursorActive: boardCursorActive, keyboardOwner: keyboardOwner,
            showMinimap: showMinimap,
            minimapScale: minimapScale, useQuestionMarks: useQuestionMarks)
    }
}

/// The scene-property pushes shared by both platform representables.
private func applyScene(
    _ scene: BoardScene, palette: Palette, showMinimap: Bool, minimapScale: Double,
    useQuestionMarks: Bool
) {
    scene.palette = palette
    scene.showMinimap = showMinimap
    scene.minimapScale = CGFloat(minimapScale)
    scene.useQuestionMarks = useQuestionMarks
}

#if os(macOS)
private struct BoardSKView: NSViewRepresentable {
    let scene: BoardScene
    let palette: Palette
    let inputMode: InputMode
    let boardCursorActive: Bool
    let keyboardOwner: Bool
    let showMinimap: Bool
    let minimapScale: Double
    let useQuestionMarks: Bool

    func makeNSView(context: Context) -> ScrollForwardingSKView {
        let view = ScrollForwardingSKView()
        view.ignoresSiblingOrder = true
        applyScene(
            scene, palette: palette, showMinimap: showMinimap, minimapScale: minimapScale,
            useQuestionMarks: useQuestionMarks)
        view.inputMode = inputMode
        view.boardCursorActive = boardCursorActive
        view.keyboardOwner = keyboardOwner
        view.presentScene(scene)
        return view
    }

    func updateNSView(_ view: ScrollForwardingSKView, context: Context) {
        if view.scene !== scene { view.presentScene(scene) }
        applyScene(
            scene, palette: palette, showMinimap: showMinimap, minimapScale: minimapScale,
            useQuestionMarks: useQuestionMarks)
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
#else
private struct BoardSKView: UIViewRepresentable {
    let scene: BoardScene
    let palette: Palette
    let inputMode: InputMode  // unused on iOS (no pointer cursor)
    let boardCursorActive: Bool  // unused on iOS (no pointer cursor)
    let keyboardOwner: Bool
    let showMinimap: Bool
    let minimapScale: Double
    let useQuestionMarks: Bool

    func makeUIView(context: Context) -> KeyForwardingSKView {
        let view = KeyForwardingSKView()
        view.ignoresSiblingOrder = true
        applyScene(
            scene, palette: palette, showMinimap: showMinimap, minimapScale: minimapScale,
            useQuestionMarks: useQuestionMarks)
        view.keyboardOwner = keyboardOwner
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ view: KeyForwardingSKView, context: Context) {
        if view.scene !== scene { view.presentScene(scene) }
        applyScene(
            scene, palette: palette, showMinimap: showMinimap, minimapScale: minimapScale,
            useQuestionMarks: useQuestionMarks)
        view.keyboardOwner = keyboardOwner
        // While the board owns the keyboard, hold first responder so a
        // hardware keyboard (iPad) drives the cursor. Never under a modal —
        // a sheet's text field must not be robbed.
        if keyboardOwner, !view.isFirstResponder, view.window != nil {
            DispatchQueue.main.async { [weak view] in
                guard let view, view.window != nil, !view.isFirstResponder else { return }
                view.becomeFirstResponder()
            }
        }
    }
}

/// An `SKView` that maps hardware-keyboard presses (iPad, or a paired keyboard
/// on iPhone) onto the same `BoardKeyCommand`s the Mac's keyDown drives.
final class KeyForwardingSKView: SKView {
    /// Whether the board owns the hardware keyboard. False on the title and
    /// under modals: handled keys are dropped and first responder is resigned
    /// — Esc on the title must NOT resume the hidden game, and arrows must
    /// not reveal cells blind.
    var keyboardOwner = false {
        didSet {
            guard keyboardOwner != oldValue, !keyboardOwner else { return }
            if isFirstResponder { resignFirstResponder() }
        }
    }

    override var canBecomeFirstResponder: Bool { true }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard keyboardOwner, let board = scene as? BoardScene else {
            return super.pressesBegan(presses, with: event)
        }
        var handled = false
        for press in presses {
            guard let key = press.key, let command = Self.command(for: key) else { continue }
            board.perform(command)
            handled = true
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }

    private static func command(for key: UIKey) -> BoardKeyCommand? {
        switch key.keyCode {
        case .keyboardUpArrow: return .move(dx: 0, dy: 1)  // rows render bottom-up
        case .keyboardDownArrow: return .move(dx: 0, dy: -1)
        case .keyboardLeftArrow: return .move(dx: -1, dy: 0)
        case .keyboardRightArrow: return .move(dx: 1, dy: 0)
        case .keyboardReturnOrEnter, .keypadEnter: return .activate
        case .keyboardF: return .flag
        case .keyboardSpacebar: return .toggleMode
        case .keyboardEscape: return .pauseResume
        default: return BoardKeyCommand.wasd(key.charactersIgnoringModifiers)
        }
    }
}
#endif
