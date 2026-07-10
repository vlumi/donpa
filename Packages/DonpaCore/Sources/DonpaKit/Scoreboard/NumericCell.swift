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
/// (`ScoreboardView.columnHeader`) stay aligned from one source.
///
/// These are BASE widths at the default text size: each using view multiplies by
/// its own `@ScaledMetric(relativeTo: .body)` factor (`ScoreColumns.baseScale`'s
/// doc pattern) so the columns grow with Dynamic Type — fixed columns forced
/// grown values to shrink back toward half size, defeating the enlargement in
/// exactly the numbers a low-vision reader wants big. `numericCell` stays as the
/// safety net for the rare over-long value.
enum ScoreColumns {
    static let cleared: CGFloat = 56
    static let bestProgress: CGFloat = 64
    /// The Best-time column is sized for the COMMON case — a badge + new-best arrow +
    /// `m:ss.t` (e.g. `↑ ① 9:59.9`) at full size. Rare longer values (10+ min, or a
    /// marathon XXXL that rolls into `h:mm:ss.t`) shrink via `numericCell` rather than
    /// widening the column and stealing width from the title on iPhone SE portrait.
    static let bestTime: CGFloat = 100
}
