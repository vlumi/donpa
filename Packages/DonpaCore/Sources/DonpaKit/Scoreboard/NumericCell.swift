import SwiftUI

extension View {
    /// A numeric/time cell in the score tables: never wraps, shrinks to fit its
    /// fixed-width column instead.
    func numericCell() -> some View {
        lineLimit(1).minimumScaleFactor(0.5)
    }
}

/// Shared base column widths so `ScoreRow` and the header stay aligned; each view
/// multiplies by its own `@ScaledMetric` factor so the columns grow with Dynamic Type.
enum ScoreColumns {
    static let cleared: CGFloat = 56
    static let bestProgress: CGFloat = 64
    /// Sized for the common case (badge + new-best arrow + `m:ss.t`); rare longer
    /// values shrink via `numericCell` rather than stealing width from the title
    /// on iPhone SE portrait.
    static let bestTime: CGFloat = 100
}
