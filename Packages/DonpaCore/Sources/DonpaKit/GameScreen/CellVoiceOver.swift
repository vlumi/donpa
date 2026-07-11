import DonpaCore
import Foundation
import SwiftUI

/// The focused cell's spoken description — the cursor IS the board's VoiceOver
/// interface (per-cell elements can't scale to a million-cell board, so one
/// navigable element describes wherever the cursor stands). Rows are spoken
/// top-down (row 1 = the top row): the board renders rows bottom-up, so the
/// raw index flips, and "move up" then decreases the spoken row as expected.
enum CellVoiceOver {
    static func describe(_ cell: Cell, at c: Coord, boardHeight: Int) -> String {
        String(
            format: String(localized: "Row %1$lld, column %2$lld: %3$@", bundle: .module),
            boardHeight - c.y, c.x + 1, state(of: cell))
    }

    private static func state(of cell: Cell) -> String {
        switch cell.state {
        case .hidden: return String(localized: "hidden", bundle: .module)
        case .flagged: return String(localized: "flagged", bundle: .module)
        case .questioned: return String(localized: "question mark", bundle: .module)
        case .revealed:
            // A revealed mine only exists on a lost board (the hit tile).
            if cell.isMine { return String(localized: "mine", bundle: .module) }
            if cell.adjacentMines == 0 {
                return String(localized: "open, clear", bundle: .module)
            }
            return String(
                format: String(localized: "open, %lld", bundle: .module),
                cell.adjacentMines)
        }
    }
}

/// The board's cursor-driven accessibility: one VoiceOver element whose value
/// describes the focused cell (the whole-board summary until a cursor exists),
/// custom actions to move and act on it, and a spoken announcement per change.
/// A modifier (not inline on `board`) so the view expression stays small enough
/// to type-check.
struct BoardCellA11y: ViewModifier {
    @ObservedObject var viewModel: GameViewModel
    let scene: BoardScene
    /// The no-cursor fallback value (config, size, mines remaining, state).
    let summary: String

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Board", bundle: .module))
            .accessibilityValue(value)
            .accessibilityIdentifier("game.board")
            .accessibilityAction(named: Text("Move up", bundle: .module)) {
                scene.moveCursor(dx: 0, dy: 1)  // rows render bottom-up: up = +y
            }
            .accessibilityAction(named: Text("Move down", bundle: .module)) {
                scene.moveCursor(dx: 0, dy: -1)
            }
            .accessibilityAction(named: Text("Move left", bundle: .module)) {
                scene.moveCursor(dx: -1, dy: 0)
            }
            .accessibilityAction(named: Text("Move right", bundle: .module)) {
                scene.moveCursor(dx: 1, dy: 0)
            }
            .accessibilityAction(named: Text("Dig or chord", bundle: .module)) {
                scene.activateCursor()
            }
            .accessibilityAction(named: Text("Flag", bundle: .module)) {
                scene.flagCursor()
            }
            // Speak every cursor move, and the focused cell's new state once an
            // action changes the board under it (no-op without a screen reader).
            .onChangeCompat(of: viewModel.focusedCell) { focused in
                guard let focused else { return }
                A11yAnnounce.post(spoken(focused))
            }
            .onChangeCompat(of: viewModel.revision) { _ in
                guard let focused = viewModel.focusedCell else { return }
                A11yAnnounce.post(spoken(focused))
            }
    }

    private var value: String {
        if let focused = viewModel.focusedCell { return spoken(focused) }
        return summary
    }

    private func spoken(_ c: Coord) -> String {
        CellVoiceOver.describe(
            viewModel.game.board[c], at: c, boardHeight: viewModel.boardHeight)
    }
}
