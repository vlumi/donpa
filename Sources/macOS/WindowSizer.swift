import AppKit
import DonpaCore

/// Grows the key window when a board needs more room — never shrinks, so a
/// maximized or hand-sized window is respected. Basic boards only: presets
/// vary in shape (9×9 … 30×16), so fitting the window to the board works;
/// Grid/Hive are square up to 1024×1024, where growing to fit would maximize
/// off-puttingly — they stay panned/zoomed within the current window.
enum WindowSizer {
    /// Target board area (points) used to derive a comfortable cell size, so a
    /// freshly-opened small window lands at a substantial size rather than tiny.
    private static let targetBoardWidth: CGFloat = 760
    private static let targetBoardHeight: CGFloat = 600
    /// Cell-size clamp for the *minimum* fit: a cap so small boards don't demand
    /// a giant window, a floor so dense boards stay clickable.
    private static let maxCellSize: CGFloat = 72
    private static let minCellSize: CGFloat = 24
    /// Approximate chrome height (status bar + difficulty pickers) added below
    /// the board area.
    private static let chromeHeight: CGFloat = 140
    private static let boardPadding: CGFloat = 24

    static func growToFit(for config: GameConfig) {
        guard case .basic = config else { return }
        growToFit(forBoard: config.width, by: config.height)
    }

    private static func growToFit(forBoard cols: Int, by rows: Int) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else {
            return
        }
        // Don't fight the user in full screen.
        guard !window.styleMask.contains(.fullScreen) else { return }

        // Largest cell that fits both target dimensions, then clamped — this is
        // the *minimum* comfortable window for the board.
        let fit = min(targetBoardWidth / CGFloat(cols), targetBoardHeight / CGFloat(rows))
        let cell = min(maxCellSize, max(minCellSize, fit))

        let needW = CGFloat(cols) * cell + boardPadding * 2
        let needH = CGFloat(rows) * cell + boardPadding + chromeHeight

        let current = window.contentRect(forFrameRect: window.frame).size
        var content = CGSize(
            width: max(needW, current.width),
            height: max(needH, current.height))

        if let frame = window.screen?.visibleFrame {
            content.width = min(content.width, frame.width - 40)
            content.height = min(content.height, frame.height - 40)
        }
        content.width = max(content.width, 420)
        content.height = max(content.height, 560)

        guard content.width > current.width + 1 || content.height > current.height + 1 else {
            return
        }
        window.setContentSize(content)
    }
}
