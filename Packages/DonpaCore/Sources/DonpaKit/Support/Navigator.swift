import DonpaCore
import SwiftUI

/// Shared navigation state, outside `GameView`'s private `@State` so hosts (e.g.
/// the macOS menu bar) can also drive sheet presentation and the title command.
@MainActor
public final class Navigator: ObservableObject {
    /// Whether the title card is showing over the game.
    @Published public var showingTitle: Bool
    /// Whether the scoreboard sheet is presented.
    @Published public var showingScores = false
    /// Whether the settings sheet is presented.
    @Published public var showingSettings = false
    /// Whether the About sheet is presented.
    @Published public var showingAbout = false
    /// Whether the New Game config popup is presented.
    @Published public var showingNewGame = false

    /// Bumped on a title-art tap. `GameContent` routes it (resume a saved game, or
    /// open the New Game popup). A counter, not a Bool, so repeated taps fire.
    @Published public var startRequested = 0

    /// Bumped to "go home". Routed through `GameContent` rather than setting
    /// `showingTitle` directly, so going home pauses and saves rather than discards.
    @Published public var homeRequested = 0

    /// Bumped to zoom in / out (macOS ⌘+ / ⌘−). Routed to the board scene, which
    /// zooms about the centre (keyboard has no cursor). Mouse/trackpad zoom is
    /// separate.
    @Published public var zoomInRequested = 0
    @Published public var zoomOutRequested = 0

    /// Bumped to toggle the minimap between its min and max size (macOS ⌘0).
    @Published public var toggleMinimapRequested = 0

    /// Set to start a fresh game on a specific config — the scoreboard's "New game
    /// on this board". `GameView` observes it, starts the game, dismisses the
    /// scoreboard, and leaves the title. Cleared back to nil after handling.
    @Published public var playConfigRequested: GameConfig?

    /// Whether any modal is presented. Gameplay commands are disabled while one is
    /// up, so their keyboard shortcuts don't mutate the game underneath.
    public var isModalPresented: Bool {
        showingScores || showingSettings || showingAbout || showingNewGame
            || incomingShare != nil
    }

    /// A received share awaiting the user's decision (opened via a donpa.app link or
    /// scanned QR). Drives the receive prompt — the confirm sheet for a new/refreshed
    /// friend, the resolution sheet for a name collision, or the alert for a share
    /// that failed to verify. Cleared once handled.
    @Published public var incomingShare: IncomingShare?

    public init(showingTitle: Bool = true) {
        self.showingTitle = showingTitle
    }
}

/// A decoded incoming share plus the classification the receive UI branches on. The
/// URL is decoded once (in `GameView.receive(url:)`) and the result carried here so
/// the sheet/alert just renders — no re-decoding, no signature check in the view.
public enum IncomingShare: Identifiable {
    /// Verified, and a genuine new/refresh/migrate — show the confirm sheet.
    case accepted(SharePayload, FriendMerge.Outcome)
    /// Verified, but the name clashes with an existing friend (different key) — show
    /// the keep-both / replace / cancel resolution sheet. Carries the clashing key.
    case collision(SharePayload, existingKey: Data)
    /// Failed to verify or decode — show the loud alert with a reason.
    case failed(ShareCodec.DecodeError)

    /// Stable identity for `.sheet(item:)` — one live prompt at a time, so a constant
    /// per-case tag is enough (and avoids hashing the payload).
    public var id: String {
        switch self {
        case .accepted: return "accepted"
        case .collision: return "collision"
        case .failed: return "failed"
        }
    }
}
