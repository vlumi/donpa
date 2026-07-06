import SwiftUI

extension View {
    /// A numeric/time cell in the score tables: never wraps, shrinks to fit its
    /// column instead. The scoreboard's time and count columns are fixed-width so
    /// they line up, and a value like `0:11.7` used to wrap to two lines ("0:11." /
    /// "7") when the column was a touch narrow — squeezing it down reads far better
    /// than a wrapped cell (or a mid-row height jump).
    func numericCell() -> some View {
        lineLimit(1).minimumScaleFactor(0.5)
    }
}
