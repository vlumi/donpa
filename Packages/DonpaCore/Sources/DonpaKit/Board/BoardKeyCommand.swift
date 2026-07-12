import DonpaCore
import Foundation

/// One vocabulary for the board's raw-key handling on BOTH platforms: the
/// macOS `keyDown` and the iPad `pressesBegan` translate events to commands
/// and `BoardScene.perform` runs them — two thin maps that can't drift apart
/// (they already had: WASD was layout-following on Mac but positional on
/// iPad).
enum BoardKeyCommand {
    case move(dx: Int, dy: Int)
    /// Dig — or chord a revealed number, following the input mode.
    case activate
    case flag
    case toggleMode
    case pauseResume

    /// WASD by TYPED character, so it follows the user's layout everywhere.
    /// Rows render bottom-up: visual up = +y.
    static func wasd(_ characters: String?) -> BoardKeyCommand? {
        switch characters?.lowercased() {
        case "w": return .move(dx: 0, dy: 1)
        case "s": return .move(dx: 0, dy: -1)
        case "a": return .move(dx: -1, dy: 0)
        case "d": return .move(dx: 1, dy: 0)
        default: return nil
        }
    }
}

extension BoardScene {
    func perform(_ command: BoardKeyCommand) {
        switch command {
        case .move(let dx, let dy): moveCursor(dx: dx, dy: dy)
        case .activate: activateCursor()
        case .flag: flagCursor()
        case .toggleMode: viewModel.inputMode.toggle()
        case .pauseResume:
            if viewModel.isPaused { viewModel.resume() } else { viewModel.pause() }
        }
    }
}
