import SwiftUI

/// A monotonic "do X now" signal across a view boundary, for actions living in
/// a child's private state: fire on the host; the child reacts via `onPulse`.
struct Pulse: Equatable {
    private(set) var count = 0
    mutating func fire() { count += 1 }
}

extension View {
    /// Runs `action` on each `fire()`; never for the initial value.
    func onPulse(_ pulse: Pulse, perform action: @escaping () -> Void) -> some View {
        onChangeCompat(of: pulse) { fired in
            guard fired != Pulse() else { return }
            action()
        }
    }
}
