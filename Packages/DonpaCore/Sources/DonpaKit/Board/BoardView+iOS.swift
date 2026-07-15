#if os(iOS)
import DonpaCore
import SpriteKit
import SwiftUI

struct BoardSKView: UIViewRepresentable {
    let scene: BoardScene
    let palette: Palette
    let inputMode: InputMode  // unused on iOS (no pointer cursor)
    let boardCursorActive: Bool  // unused on iOS (no pointer cursor)
    let keyboardOwner: Bool
    let minimap: MinimapPrefs
    let useQuestionMarks: Bool

    func makeUIView(context: Context) -> KeyForwardingSKView {
        let view = KeyForwardingSKView()
        view.ignoresSiblingOrder = true
        applyScene(scene, palette: palette, minimap: minimap, useQuestionMarks: useQuestionMarks)
        view.keyboardOwner = keyboardOwner
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ view: KeyForwardingSKView, context: Context) {
        if view.scene !== scene { view.presentScene(scene) }
        applyScene(scene, palette: palette, minimap: minimap, useQuestionMarks: useQuestionMarks)
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
