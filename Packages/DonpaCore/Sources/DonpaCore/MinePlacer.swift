/// Places mines after the first click so the opening reveal is always safe.
///
/// The safety zone is the first-clicked cell *and all of its neighbours*. With
/// no mine adjacent to the first cell, that cell is guaranteed to be a 0 and the
/// flood-fill opens a region — satisfying the "first click always hits a 0"
/// requirement. The zone is computed via `topology.neighbors`, so it works
/// identically on wrapped and hex boards.
public struct MinePlacer {
    /// Returns the set of coordinates that should hold mines.
    ///
    /// - Parameters:
    ///   - topology: board geometry.
    ///   - mineCount: how many mines to place.
    ///   - firstClick: the cell the player opened first; it and its neighbours
    ///     are kept mine-free.
    ///   - rng: injected for reproducible tests.
    public static func placeMines<R: RandomNumberGenerator>(
        topology: any RectangularTopology,
        mineCount: Int,
        firstClick: Coord,
        using rng: inout R
    ) -> Set<Coord> {
        var safeZone: Set<Coord> = [firstClick]
        safeZone.formUnion(topology.neighbors(of: firstClick))

        let cellCount = topology.cellCount
        let available = cellCount - safeZone.count

        // Sparse case (the norm): rejection-sample random flat indices and skip the
        // safe zone, until we have `mineCount` distinct mines. O(mineCount) and —
        // crucially on a 1000² board — it never materializes or filters all 1M
        // coords (the old `allCoords().filter`, slow through `AnySequence`). When
        // the board is dense enough that rejection would thrash (few free cells
        // left), fall back to shuffling the explicit candidate list.
        if mineCount <= available, available > 0, mineCount * 4 <= available * 3 {
            var mines = Set<Coord>()
            mines.reserveCapacity(mineCount)
            while mines.count < mineCount {
                let c = topology.coord(at: Int.random(in: 0..<cellCount, using: &rng))
                if !safeZone.contains(c) { mines.insert(c) }
            }
            return mines
        }

        // Dense fallback: build the candidate list (excluding the safe zone, or —
        // if the board is so full that even that can't fit the mines — only the
        // clicked cell), then partial-Fisher–Yates `mineCount` of them.
        var candidates = topology.allCoords().filter { !safeZone.contains($0) }
        if candidates.count < mineCount {
            candidates = topology.allCoords().filter { $0 != firstClick }
        }
        let take = min(mineCount, candidates.count)
        for i in 0..<take {
            let j = Int.random(in: i..<candidates.count, using: &rng)
            candidates.swapAt(i, j)
        }
        return Set(candidates.prefix(take))
    }
}
