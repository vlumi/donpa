import Foundation

/// The "full clear" meta-score: the summed best times across a GROUP of configs —
/// a size's densities, or Basic's three presets. Comparable only when every config
/// in the group has a winning time (a sum with holes would reward playing less),
/// so `sumCentiseconds` stays nil until the group is fully cleared. Grouping by
/// size keeps the terms comparable — summing across sizes would make XXXL dwarf
/// everything else into a rounding error.
public enum FullClear {
    public struct Standing: Equatable, Sendable {
        public let cleared: Int
        public let total: Int
        /// The full-clear sum, present only once EVERY config in the group is won.
        public let sumCentiseconds: Int?
    }

    /// One group's standing from its configs' best times (nil = not won yet).
    public static func standing(bests: [Int?]) -> Standing {
        let cleared = bests.compactMap { $0 }
        let complete = !bests.isEmpty && cleared.count == bests.count
        return Standing(
            cleared: cleared.count, total: bests.count,
            sumCentiseconds: complete ? cleared.reduce(0, +) : nil)
    }
}
