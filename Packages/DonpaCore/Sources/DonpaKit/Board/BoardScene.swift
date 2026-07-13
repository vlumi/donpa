import DonpaCore
import SpriteKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Renders the board with an `SKCameraNode` for pan/zoom. Cell nodes are rebuilt
/// from the view model whenever its revision changes.
public final class BoardScene: SKScene {
    let viewModel: GameViewModel
    /// Pixel layout for the current board, derived from the live config so it
    /// follows a shape switch (square ↔ hex) on New Game — the scene is long-lived
    /// and rebuilds on `gameID` change, so a stored constant would go stale.
    var layout: any CellLayout { viewModel.config.layout() }
    let cameraNode = SKCameraNode()
    let boardLayer = SKNode()
    /// End-game effects, a sibling of `boardLayer` so `rebuild()` (which clears
    /// `boardLayer`) never wipes an in-flight animation.
    let effectsLayer = SKNode()
    /// Mode-glow wash over unopened tiles: above `boardLayer`, below `effectsLayer`.
    /// Never wiped by `rebuild()`.
    let glowLayer = SKNode()
    /// The focused-cell cursor's own layer: above the glow, below effects; its own
    /// so neither the glow refresh (wipes `glowLayer`) nor the idle throttle
    /// (`effectsLayer` children force active FPS) touches it.
    let cursorLayer = SKNode()
    // Render state — read/written by BoardScene+Render.
    var lastRevision = -1
    var lastGameID = -1
    var lastAnimatedResultID = -1
    /// Built cell nodes under `boardLayer`, keyed by coord. Only **visible** cells
    /// (camera rect + margin) are built, so the live node count stays ~one
    /// screenful regardless of board size. A board that fits holds every cell.
    var cellNodes: [Coord: SKNode] = [:]
    /// The cell range last built, so a viewport change only touches the delta.
    var builtRange: CellRange?
    // Mode-glow state, compared each frame so the glow only rebuilds on change.
    var lastGlowMode: InputMode?
    var lastGlowLive: Bool?
    var lastGlowRevision = -1
    /// Visible range the glow was last stamped for, so it re-stamps on scroll too.
    var lastGlowRange: CellRange?
    /// Screentone wash textures, keyed by mode + cell-size/appearance tag.
    var glowTextureCache: [String: SKTexture] = [:]
    /// Tile-background and glyph textures, keyed by role + pixel size + colour.
    /// Every visible cell is an `SKSpriteNode` sharing one of these, so SpriteKit
    /// batches same-texture sprites into one draw call (cheaper than per-cell
    /// `SKShapeNode` on big boards).
    var tileTextureCache: [String: SKTexture] = [:]

    // Focused-cell cursor (keyboard/VoiceOver navigation) — BoardScene+Cursor.
    /// The cursor's SCREEN cell — unclamped on wrapped boards, like `cellNodes`
    /// keys; the logical cell it focuses is `displayCoord` of this, mirrored to
    /// `viewModel.focusedCell` for the chrome. nil until the first move.
    var cursorScreenCoord: Coord?
    /// The single ring node marking the cursor, on its own layer above the glow.
    var cursorNode: SKSpriteNode?
    /// Ring visibility tracks the INPUT SOURCE: a mouse click hides it (the
    /// position still follows, so arrows resume from the click), any cursor
    /// key shows it again.
    var cursorRingHidden = false

    // Minimap — corner thumbnail of the whole board with a viewport rectangle,
    // shown only when the board exceeds the view. Lives in BoardScene+Minimap;
    // pinned to the camera so it's screen-fixed.
    var minimapNode: SKNode?
    var minimapPanel: SKShapeNode?
    var minimapImage: SKSpriteNode?
    var minimapViewport: SKShapeNode?
    var minimapHandle: SKNode?
    /// The minimap image's rect in CAMERA space (screen-fixed) — the tap/drag hit
    /// area for navigating the board via the minimap. nil while hidden.
    var minimapImageRect: CGRect?
    var lastMinimapRevision = -1
    var lastMinimapBoard: CGSize = .zero
    /// Show the minimap when the board exceeds the viewport (user preference).
    var showMinimap = true
    /// Whether the flag cycle includes the "?" step (Settings.questionMarks), pushed
    /// from the host like `showMinimap`. Read by the flag input paths.
    var useQuestionMarks = false
    /// Plays the input sound effects (flag/chord/reveal). The host owns it and keeps
    /// its `isEnabled` in step with Settings; nil until wired (tests, previews).
    weak var soundPlayer: SoundPlayer?
    /// Fires the per-action haptics (flag/chord; reveal is driven by the VM's
    /// onReveal so it can scale by cascade size). Host-owned, like `soundPlayer`.
    weak var hapticPlayer: HapticPlayer?
    /// Minimap size multiplier (persisted in Settings), clamped when applied.
    var minimapScale: CGFloat = 1
    /// Whether a drag in progress began on the minimap, so the whole drag scrubs
    /// the board via the minimap instead of panning.
    var scrubbingMinimap = false
    /// Whether a drag began on the minimap RESIZE HANDLE, so it resizes the minimap
    /// rather than scrubbing or panning.
    var resizingMinimap = false
    /// The resize handle's hit area in CAMERA space — an L of two overlapping rects
    /// (a vertical arm along the minimap's right edge + a horizontal arm along the
    /// bottom), hugging the corner. Empty while hidden.
    var minimapHandleRects: [CGRect] = []
    /// Push a new minimap scale to the host, which persists it in Settings.
    var onMinimapScaleChange: ((CGFloat) -> Void)?
    /// The in-flight minimap-overview render. A burst of board revisions (e.g. a big
    /// flood-fill reveal on a huge board) would otherwise spawn one full 1M-cell
    /// raster per revision and pile them onto the cooperative pool, pegging every
    /// core long after the reveal finished. Cancel the prior render before starting
    /// the next so only the latest runs.
    var minimapRenderTask: Task<Void, Never>?

    /// A saved camera view to hold across the launch dance instead of the default
    /// fit. STICKY: the window settles to its restored frame *after* the scene
    /// mounts, firing `didMove`/`didChangeSize` which would each re-centre — so the
    /// target is re-applied at every such point until the player pans/zooms (or
    /// starts a new game), then cleared.
    var restoreCameraTarget: CameraView?

    /// Set by the host on appearance change; recolors the background and rebuilds.
    public var palette: Palette = .dark {
        didSet {
            // BoardView re-assigns on EVERY SwiftUI update; the guard keeps
            // that from forcing a full board rebuild each time.
            guard palette != oldValue else { return }
            backgroundColor = palette.sceneBackground
            rebuild()
            lastGlowMode = nil  // force the glow to recolor from the new palette
            recolorMinimap()  // its colours are baked at build; force a redo
        }
    }

    public init(viewModel: GameViewModel) {
        self.viewModel = viewModel
        super.init(size: CGSize(width: 320, height: 320))
        scaleMode = .resizeFill
        backgroundColor = palette.sceneBackground
        // Layer order is by zPosition, not add-order: the SKView sets
        // `ignoresSiblingOrder = true`, so equal-z siblings draw in undefined order.
        // Without an explicit higher z the glow's `SKShapeNode` tiles batch under
        // the opaque sprite tiles and vanish.
        boardLayer.zPosition = 0
        glowLayer.zPosition = 1  // above tiles…
        cursorLayer.zPosition = 1.5  // …cursor over the glow…
        effectsLayer.zPosition = 2  // …but below end-game effects
        addChild(boardLayer)
        addChild(glowLayer)
        addChild(cursorLayer)
        addChild(effectsLayer)
        addChild(cameraNode)
        camera = cameraNode
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func didMove(to view: SKView) {
        super.didMove(to: view)
        rebuildIfNeeded()
        applyDesiredCameraOrCenter()
        installGestureRecognizers(on: view)
    }

    // Idle render throttle: a board that isn't animating is a STATIC image, but
    // SpriteKit re-walks and re-batches every visible node 60×/sec regardless —
    // ~30% CPU at rest on a huge board (release; far worse in debug), pure waste on a
    // turn-based game. So drop the view's frame rate to a trickle once nothing has
    // changed for a grace period, and snap back to full rate on any activity. The
    // trickle keeps `update()` running so this self-resumes (vs. `isPaused`, which
    // would halt `update()` and need waking from every input path).
    // 10fps idle keeps worst-case input-wake latency ~100ms (imperceptible to start a
    // grab-pan, which carries inertia anyway) while cutting idle render ~6×; the
    // central activity check then snaps to 60 the same frame it sees the camera move.
    private static let idleFPS = 10
    private static let activeFPS = 60
    private static let idleGrace: TimeInterval = 0.4  // settle before throttling
    private var lastActiveTime: TimeInterval = 0
    private var lastCameraSnapshot: CameraView?
    private var lastCursorSnapshot: Coord?
    private var lastActivityRevision = -1

    public override func update(_ currentTime: TimeInterval) {
        rebuildIfNeeded()
        // Cull to the viewport every frame (no-op unless the camera moved); catches
        // pan, zoom, and the animated spring-back without each calling in.
        buildVisibleCells()
        refreshModeGlow()
        refreshCursor()
        refreshMinimap()
        // Keep the live camera view current so an autosave persists the view.
        viewModel.cameraView = currentCameraView()

        applyIdleThrottle(currentTime)
    }

    /// Anything that should keep the board redrawing: an in-flight action (end-game
    /// FX, camera spring-back), a state change (a reveal/flag bumps `revision`, a new
    /// game bumps `gameID`), or a camera move (pan/zoom/scroll — caught by comparing
    /// the camera transform rather than hooking every input handler).
    private func isAnimating() -> Bool {
        if cameraNode.hasActions() || boardLayer.hasActions() { return true }
        if !effectsLayer.children.isEmpty { return true }
        if viewModel.revision != lastActivityRevision || viewModel.gameID != lastGameID {
            return true
        }
        // A cursor move counts as activity (it doesn't bump `revision` or move the
        // camera when the target is already on-screen — at idle FPS it would lag).
        if cursorScreenCoord != lastCursorSnapshot { return true }
        // Camera move (pan/zoom/scroll/spring) — compared via the transform rather
        // than hooking every input handler, so no path can forget to wake the view.
        return currentCameraView() != lastCameraSnapshot
    }

    private func applyIdleThrottle(_ currentTime: TimeInterval) {
        if isAnimating() {
            lastActiveTime = currentTime
            lastActivityRevision = viewModel.revision
            lastCameraSnapshot = currentCameraView()
            lastCursorSnapshot = cursorScreenCoord
        }
        let idle = currentTime - lastActiveTime > Self.idleGrace
        let target = idle ? Self.idleFPS : Self.activeFPS
        if view?.preferredFramesPerSecond != target {
            view?.preferredFramesPerSecond = target
        }
    }

    // MARK: Rendering — cell nodes + viewport culling live in BoardScene+Render.

    /// Play a one-shot end-game animation (implemented in BoardScene+Effects).
    func playEndGameEffects(_ result: GameResult) {
        effectsLayer.removeAllChildren()
        switch result {
        case .lost(let at): playLoss(trigger: at, reduceMotion: Self.prefersReducedMotion)
        case .won: playWin(reduceMotion: Self.prefersReducedMotion)
        }
    }

    // MARK: Camera

    /// Max on-screen cell size as a fraction of the viewport's smaller side, so a
    /// tiny board can't blow up to where a few cells fill the screen.
    private static let maxCellFractionOfViewport: CGFloat = 0.22
    private static let absoluteMaxCellSize: CGFloat = 140
    /// Cap on cells the *initial* zoom shows. Render cost is per-visible-cell, so
    /// bounding the visible count (not cell size) keeps a fresh huge board fast on
    /// any window size.
    private static let maxStartVisibleCells: CGFloat = 600
    /// Floor so a cell never *starts* smaller than comfortably tappable; the player
    /// can still zoom further out manually.
    private static let minStartCellSize: CGFloat = 28
    /// When the board exceeds the viewport, nudge the start zoom in so edge cells
    /// clip mid-cell, signalling the board continues. <1 because scale is
    /// world-units-per-point (smaller = more zoomed in).
    private static let edgePeekZoom: CGFloat = 0.92
    /// Smallest on-screen cell reachable by manual zoom-out — a small buffer past
    /// the start floor, never into the tiny/choppy range on a huge board.
    private static let minInteractiveCellSize: CGFloat = 22

    /// Most zoomed-out scale allowed: whichever of "whole board fits" / "cells at
    /// the min interactive size" keeps cells tappable (the smaller scale).
    var maxZoomOutScale: CGFloat {
        let interactiveLimit = layout.cellSize / Self.minInteractiveCellSize
        return min(fitScale, interactiveLimit)
    }

    func centerCamera() {
        let board = layout.boardSize(width: viewModel.boardWidth, height: viewModel.boardHeight)
        cameraNode.position = CGPoint(x: board.width / 2, y: board.height / 2)
        // Scale = world-units-per-point; larger = more zoomed out, cell size =
        // layout.cellSize / scale.
        let viewportMin = min(size.width, size.height)
        let maxCell = min(
            Self.absoluteMaxCellSize, max(40, viewportMin * Self.maxCellFractionOfViewport))
        let cellFloor = layout.cellSize / maxCell
        // Start cell large enough that no more than `maxStartVisibleCells` fit, but
        // never below the legibility floor.
        let area = max(1, size.width * size.height)
        let startCell = max(Self.minStartCellSize, (area / Self.maxStartVisibleCells).squareRoot())
        let cellCeiling = layout.cellSize / startCell
        // Prefer to fit the whole board, clamped into [cellFloor, cellCeiling].
        var scale = min(max(fitScale, cellFloor), cellCeiling)
        // Board bigger than the viewport: nudge zoom in so edge cells clip mid-cell.
        if scale < fitScale {
            scale *= Self.edgePeekZoom
        }
        cameraNode.setScale(scale)
    }

    /// Smallest scale that still fits the whole board (the zoomed-out limit).
    var fitScale: CGFloat {
        let board = layout.boardSize(width: viewModel.boardWidth, height: viewModel.boardHeight)
        guard size.width > 0, size.height > 0,
            board.width > 0, board.height > 0
        else { return 1 }
        let margin: CGFloat = 1.1
        return max(board.width * margin / size.width, board.height * margin / size.height)
    }

    public override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        applyDesiredCameraOrCenter()
    }

    // Input/gesture/mouse/keyboard handling lives in BoardScene+Input.swift; the
    // mutable state it uses is declared here (extensions can't hold stored props).
    #if os(iOS)
    var lastPan: CGPoint = .zero
    #elseif os(macOS)
    // Left mouse: a press that stays put is a click; one that moves past the
    // threshold is a drag-pan (suppressing the click). The threshold absorbs the
    // pixel or two of click jitter that must not count as a drag.
    var lastDragViewPoint: CGPoint = .zero
    var mouseDownViewPoint: CGPoint = .zero
    var mouseDownTimestamp: TimeInterval = 0
    var didDragInScene = false
    /// Trace-only (`-donpa.inputtrace`) app-level mouse monitor — held so it lives
    /// as long as the scene; nil in normal runs. See `installGestureRecognizers`.
    var traceEventMonitor: Any?
    static let dragThreshold: CGFloat = 4
    // A drag can still END as a click: a Magic Mouse slides a few points
    // under its own click force, so a brief press whose NET down→up travel
    // stays within the slop is reclassified as a click at mouse-up.
    // Trackpads never trip this (a physical click doesn't move the pointer).
    static let clickSlop: CGFloat = 8
    static let clickMaxDuration: TimeInterval = 0.3

    /// Whether a press that crossed the drag threshold should still count as a
    /// click when released: brief AND net-travel within the slop. Pure, for tests.
    static func sloppyClickCountsAsClick(net: CGFloat, duration: TimeInterval) -> Bool {
        net <= clickSlop && duration <= clickMaxDuration
    }
    #endif
}
