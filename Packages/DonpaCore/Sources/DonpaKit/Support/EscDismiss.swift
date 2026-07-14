import SwiftUI

extension View {
    /// Dismiss on Esc: a sheet only gets a cancel key when some button declares
    /// `.cancelAction`, so this attaches an invisible one.
    func escDismisses(_ action: @escaping () -> Void) -> some View {
        background(
            Button("") { action() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        )
    }
}
