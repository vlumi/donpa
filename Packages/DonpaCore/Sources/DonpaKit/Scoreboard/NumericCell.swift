import SwiftUI

extension View {
    /// A numeric/time cell in the score tables: never wraps, shrinks to fit its
    /// column instead. The columns are fixed-width so they line up, and a value like
    /// `0:11.7` used to wrap to two lines ("0:11." / "7") when a column ran a touch
    /// narrow — squeezing it down reads far better than a wrapped cell.
    func numericCell() -> some View {
        lineLimit(1).minimumScaleFactor(0.5)
    }
}

/// Shared column widths for the high-score table, so `ScoreRow` and the header
/// (`ScoreboardView.columnHeader`) stay aligned from one source. BASE widths:
/// each view multiplies by its own `@ScaledMetric` factor so the columns grow
/// with Dynamic Type; `numericCell` stays the safety net for over-long values.
enum ScoreColumns {
    static let cleared: CGFloat = 56
    static let bestProgress: CGFloat = 64
    /// The Best-time column is sized for the COMMON case — a badge + new-best arrow +
    /// `m:ss.t` (e.g. `↑ ① 9:59.9`) at full size. Rare longer values (10+ min, or a
    /// marathon XXXL that rolls into `h:mm:ss.t`) shrink via `numericCell` rather than
    /// widening the column and stealing width from the title on iPhone SE portrait.
    static let bestTime: CGFloat = 100
}
