import Foundation

/// Hands an App Intent's request to the live UI. The intent's `perform()`
/// runs in the app process but before/independent of any view — actions
/// dispatched before the root registers are held and drained on registration
/// (the cold-launch order).
@MainActor
public final class LaunchActionRouter {
    public enum Action: Equatable, Sendable {
        case continueBoard
        case startDrills
    }

    public static let shared = LaunchActionRouter()

    private var handler: ((Action) -> Void)?
    private var pending: Action?

    public func dispatch(_ action: Action) {
        if let handler {
            handler(action)
        } else {
            pending = action
        }
    }

    public func register(_ handler: @escaping (Action) -> Void) {
        self.handler = handler
        if let pending {
            self.pending = nil
            handler(pending)
        }
    }
}
