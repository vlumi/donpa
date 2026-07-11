import SwiftUI

extension View {
    /// Dismiss the surface on Esc: a sheet only gets a cancel key when some
    /// button declares `.cancelAction`, so this attaches an invisible one —
    /// the keyboard vocabulary's "Esc backs out", on every surface. Also works
    /// for hardware keyboards on iPad.
    func escDismisses(_ action: @escaping () -> Void) -> some View {
        background(
            Button("") { action() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        )
    }
}
