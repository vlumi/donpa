import DonpaCore
import SwiftUI

/// Shared navigation state, outside `GameView`'s private `@State` so hosts (e.g.
/// the macOS menu bar) can also drive sheet presentation and the title command.
@MainActor
public final class Navigator: ObservableObject {
    @Published public var showingTitle: Bool
    @Published public var showingScores = false
    @Published public var showingSettings = false
    @Published public var showingAbout = false
    @Published public var showingHowTo = false
    @Published public var showingShortcuts = false
    @Published public var showingNewGame = false
    @Published public var showingMessHall = false

    /// A received share awaiting the user's decision (via donpa.app link or
    /// scanned QR). Drives the receive prompt; cleared once handled.
    @Published public var incomingShare: IncomingShare?

    /// Bumped whenever an in-progress save actually COMMITS to disk (write or
    /// clear). Home's Continue card and the New Game dots re-read the saves on it —
    /// crucial on big boards, where the first move can still be computing when the
    /// popup opens: the open-time flush finds nothing to save yet, and the real
    /// save lands seconds later via the debounce. A counter, so every commit fires.
    @Published public var savesChanged = 0

    /// Bumped to "go home". Routed through `GameContent` rather than setting
    /// `showingTitle` directly, so going home pauses and saves rather than discards.
    @Published public var homeRequested = 0

    /// Bumped to zoom in / out (macOS ⌘+ / ⌘−). Routed to the board scene, which
    /// zooms about the centre (keyboard has no cursor).
    @Published public var zoomInRequested = 0
    @Published public var zoomOutRequested = 0

    /// Bumped to toggle the minimap between its min and max size (macOS ⌘0).
    @Published public var toggleMinimapRequested = 0

    /// Set to start a fresh game on a specific config (the scoreboard's "New game
    /// on this board"); `GameView` observes it and clears it back to nil.
    @Published public var playConfigRequested: GameConfig?

    /// Whether any modal is presented. Gameplay commands are disabled while one is
    /// up, so their keyboard shortcuts don't mutate the game underneath.
    public var isModalPresented: Bool {
        showingScores || showingSettings || showingAbout || showingHowTo
            || showingNewGame || showingShortcuts
            || incomingShare != nil || showingMessHall
    }

    public init(showingTitle: Bool = true) {
        self.showingTitle = showingTitle
    }

    /// The daily board being attempted, nil during normal play. Set by the
    /// Home card / retry, cleared by every non-daily start path — the result
    /// recorder trusts it.
    @Published public var activeDaily: DailyChallenge.Board?
    /// The daily's pre-game review: board visible, input locked, clock not
    /// yet running; Start flips it off and performs the shared reveal.
    @Published public var dailyReviewActive = false
    @Published public var showingDailyCalendar = false
    /// Restart (the strip's Retry, ⌘R) routes here so a daily retry re-seeds
    /// the SAME board instead of minting a random one on its config.
    @Published public var restartRequested = 0

    /// Two sheet swaps in one runloop turn race; presenting the second a tick
    /// later is the reliable order. Callers dismiss first, then present here.
    public func afterDismiss(_ present: @escaping @MainActor () -> Void) {
        Task { @MainActor in present() }
    }
}

/// A decoded incoming share plus the classification the receive UI branches on.
/// The URL is decoded once (in `GameView.receive(url:)`) so the sheet/alert just
/// renders — no re-decoding, no signature check in the view.
public enum IncomingShare: Identifiable {
    /// Verified, a genuine new/refresh/migrate — the confirm sheet.
    case accepted(SharePayload, FriendMerge.Outcome)
    /// Verified, but the name clashes with an existing friend (different key) —
    /// the keep-both / replace / cancel resolution sheet.
    case collision(SharePayload, existingKey: Data)
    /// Failed to verify or decode — the loud alert with a reason.
    case failed(ShareCodec.DecodeError)
    /// The player's OWN card (same signing key) — a gentle alert, no import.
    /// Happens by scanning your own QR, or Nearby finding your other device.
    case own

    /// Stable identity for `.sheet(item:)` — one live prompt at a time, so a constant
    /// per-case tag is enough (and avoids hashing the payload).
    public var id: String {
        switch self {
        case .accepted: return "accepted"
        case .collision: return "collision"
        case .failed: return "failed"
        case .own: return "own"
        }
    }
}
