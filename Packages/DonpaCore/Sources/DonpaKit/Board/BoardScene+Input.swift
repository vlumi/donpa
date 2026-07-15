import DonpaCore
import SpriteKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// All board input: scene↔board coordinate mapping, tap/long-press/flag actions,
/// and the per-platform gesture/mouse/keyboard handlers. Mutable drag state lives
/// on `BoardScene` (extensions can't hold stored properties).
extension BoardScene {

    // MARK: Input mapping

    /// Scene-space point → board coordinate (accounting for the board layer).
    ///
    /// On a WRAPPED board a tap can land on an off-board screen position (the
    /// surface tiles infinitely), so compute the screen cell arithmetically — which
    /// may be negative or ≥ width/height — and fold it onto the real board with the
    /// topology's `normalize`. Bounded keeps the layout's bounds-guarded mapping.
    public func coord(atScenePoint p: CGPoint) -> Coord? {
        let local = boardLayer.convert(p, from: self)
        guard viewModel.game.board.cellCount > 0 else { return nil }
        if isWrapped {
            // The layout maps the (possibly off-board) screen point to a screen cell
            // — square arithmetic or nearest-hex-centre — which `normalize` folds
            // onto the torus. Never nil for a wrapped topology.
            let screen = layout.unclampedCoord(at: local)
            return viewModel.game.board.topology.normalize(screen)
        }
        return layout.coord(at: local)
    }

    /// Whether a scene point lands on the minimap HUD (the map or its resize caret).
    /// Board actions triggered by right-click / long-press / Control-click must not
    /// punch through it onto the board cell underneath.
    func isOverMinimapUI(atScenePoint p: CGPoint) -> Bool {
        guard !(minimapNode?.isHidden ?? true) else { return false }
        if minimapHandleHit(atScenePoint: p) { return true }
        guard let rect = minimapImageRect else { return false }
        return rect.contains(cameraLocal(p))
    }

    /// A plain tap/click: a revealed number chords; a hidden cell follows the
    /// current input mode (reveal or flag), so in Flag mode a stray tap can't open.
    func tapAction(atScenePoint p: CGPoint) {
        InputTrace.log(
            "scene tap \(coord(atScenePoint: p).map(String.init(describing:)) ?? "off-board")")
        if minimapHandleHit(atScenePoint: p) {
            toggleMinimapSize()
            return
        }
        if handleMinimapNavigation(atScenePoint: p) { return }
        guard let c = coord(atScenePoint: p) else { return }
        syncCursorToPointer(atScenePoint: p)
        perform(primaryActionAt: c)
    }

    /// The tap's cell routing, shared with the cursor's primary key: a revealed
    /// number chords; a hidden cell follows the current input mode.
    func perform(primaryActionAt c: Coord) {
        if viewModel.game.board[c].state == .revealed {
            chordWithSound(c)
        } else {
            switch viewModel.inputMode {
            case .reveal:
                // On a known mine, show the hit-mine tile instantly (before the
                // off-thread reveal). No-op on the safe first click.
                if viewModel.canRevealHitMine(c) { revealHitTileInstantly(at: c) }
                revealWithSound(c)
            case .flag: toggleFlagWithSound(c)
            }
        }
    }

    /// A long-press: the opposite action to the current mode on a hidden cell
    /// (flag in Reveal, reveal in Flag); chords on a revealed number, like a tap.
    func longPressAction(atScenePoint p: CGPoint) {
        guard !isOverMinimapUI(atScenePoint: p) else { return }
        guard let c = coord(atScenePoint: p) else { return }
        syncCursorToPointer(atScenePoint: p)
        if viewModel.game.board[c].state == .revealed {
            chordWithSound(c)
        } else {
            switch viewModel.inputMode {
            case .reveal: toggleFlagWithSound(c)
            case .flag: revealWithSound(c)
            }
        }
    }

    // MARK: Input + sound

    /// Toggle a flag: an up-tick when a mark is PLACED (hidden → flag, or flag →
    /// "?"), a soft downward wipe when it's CLEARED (→ hidden). Silent only on a
    /// no-op (a tap on a revealed cell).
    func toggleFlagWithSound(_ c: Coord) {
        let before = viewModel.game.board[c].state
        viewModel.toggleFlag(c, useQuestionMarks: useQuestionMarks)
        let after = viewModel.game.board[c].state
        guard after != before else { return }
        if after == .flagged || after == .questioned {
            soundPlayer?.play(.flag)
            hapticPlayer?.flag()
        } else if after == .hidden {
            // Cleared a mark.
            soundPlayer?.play(.wipe)
            hapticPlayer?.flag()
        }
    }

    /// Reveal; the OPEN feedback (sound + haptic, tick vs the fuller flood by size)
    /// fires from the VM's onReveal once the opened-cell count is final.
    private func revealWithSound(_ c: Coord) {
        viewModel.reveal(c)
    }

    /// Chord; like a reveal, its open feedback comes through onReveal (a chord is
    /// just opening several tiles), so a big chord-open floods too.
    private func chordWithSound(_ c: Coord) {
        viewModel.chord(c)
    }

    /// Map a hosting-view point to scene space via `SKView`'s own view↔scene
    /// transform (Y-flip + camera).
    func scenePoint(fromViewPoint p: CGPoint) -> CGPoint {
        convertPoint(fromView: p)
    }

    // MARK: Gesture recognizers (pan + zoom)

    func installGestureRecognizers(on view: SKView) {
        #if os(iOS)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        // No double-tap, so single taps fire immediately with no timeout.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        let long = UILongPressGestureRecognizer(target: self, action: #selector(handleLong))
        long.minimumPressDuration = 0.3
        for g in [pan, pinch, tap, long] as [UIGestureRecognizer] {
            view.addGestureRecognizer(g)
        }
        #elseif os(macOS)
        // Clicks, drag-to-pan, and right-click are handled directly via mouse
        // events (mouseDown/Dragged/Up below). Only zoom needs a recognizer.
        let pinch = NSMagnificationGestureRecognizer(target: self, action: #selector(handlePinch))
        view.addGestureRecognizer(pinch)
        // Trace-only app-level tap: logs every left-mouse-down the app
        // dispatches and WHICH view hit-tests it — an invisible overlay eating
        // clicks names itself; silence means the events die at window level.
        if InputTrace.enabled, traceEventMonitor == nil {
            traceEventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: .leftMouseDown
            ) { event in
                let hit: String
                if let cv = event.window?.contentView, let sv = cv.superview {
                    let p = sv.convert(event.locationInWindow, from: nil)
                    hit = cv.hitTest(p).map { String(describing: type(of: $0)) } ?? "none"
                } else {
                    hit = event.window == nil ? "no-window" : "no-contentView"
                }
                InputTrace.log("app mouseDown hit=\(hit)")
                return event
            }
        }
        #endif
    }
}
