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
    var minimap: MinimapPrefs = MinimapPrefs(show: true, onRight: false, scale: 1)
    var useQuestionMarks: Bool = false

    var body: some View {
        BoardSKView(
            scene: scene, palette: palette, inputMode: inputMode,
            boardCursorActive: boardCursorActive, keyboardOwner: keyboardOwner,
            minimap: minimap, useQuestionMarks: useQuestionMarks)
    }
}

/// The minimap prefs a host pushes to the scene, bundled (they travel together).
struct MinimapPrefs: Equatable {
    let show: Bool
    let onRight: Bool
    let scale: Double
}

/// The scene-property pushes shared by both platform representables.
func applyScene(
    _ scene: BoardScene, palette: Palette, minimap: MinimapPrefs, useQuestionMarks: Bool
) {
    scene.palette = palette
    scene.showMinimap = minimap.show
    scene.minimapOnRight = minimap.onRight
    scene.minimapScale = CGFloat(minimap.scale)
    scene.useQuestionMarks = useQuestionMarks
}
