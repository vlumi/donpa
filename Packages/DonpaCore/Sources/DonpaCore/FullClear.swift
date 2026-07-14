import Foundation

/// Summed best times across a group of configs (a size's densities, or Basic's
/// presets). `sumCentiseconds` stays nil until every config in the group is won —
/// a sum with holes would reward playing less. Grouped by size so the terms stay
/// comparable (XXXL would dwarf everything summed across sizes).
public enum FullClear {
    public struct Standing: Equatable, Sendable {
        public let cleared: Int
        public let total: Int
        public let sumCentiseconds: Int?
    }

    /// `bests`: one entry per config in the group, nil = not won yet.
    public static func standing(bests: [Int?]) -> Standing {
        let cleared = bests.compactMap { $0 }
        let complete = !bests.isEmpty && cleared.count == bests.count
        return Standing(
            cleared: cleared.count, total: bests.count,
            sumCentiseconds: complete ? cleared.reduce(0, +) : nil)
    }
}
