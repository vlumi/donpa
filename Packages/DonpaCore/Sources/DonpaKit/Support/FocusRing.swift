import SwiftUI

/// The keyboard focus ring: an always-present panel recoloured on focus
/// (never resizes), shared by every keyboard-navigable surface.
struct FocusRing: ViewModifier {
    let focused: Bool
    /// Ring padding — compact (short-window) mode shaves it to reclaim height.
    var inset: CGFloat = 6
    func body(content: Content) -> some View {
        content
            .padding(inset)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(focused ? 0.12 : 0))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.accentColor.opacity(focused ? 1 : 0), lineWidth: 2)))
    }
}

extension View {
    /// Keyboard focus ring — macOS only; compiles to the bare view elsewhere
    /// (the zone system is macOS-only, so iOS rings would never light up).
    @ViewBuilder
    func keyFocusRing(_ focused: Bool, inset: CGFloat = 2) -> some View {
        #if os(macOS)
        modifier(FocusRing(focused: focused, inset: inset))
        #else
        self
        #endif
    }
}
