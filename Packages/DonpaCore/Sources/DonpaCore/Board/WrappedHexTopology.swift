/// Pointy-top hexagonal geometry whose edges wrap — a hex torus. Same odd-r offset
/// coords and 6 row-parity-dependent neighbours as `HexTopology`, but `normalize`
/// folds with modulo (never `nil`), so every cell has exactly 6 neighbours and there
/// are no edges.
///
/// **Height must be even.** In odd-r, a cell's neighbour offsets depend on its row
/// parity, so a clean vertical wrap needs the top and bottom rows to have opposite
/// parity — i.e. an even row count. With an odd height the seam would pair two
/// same-parity rows, breaking adjacency symmetry (a cell's up-neighbour wouldn't
/// list it back). The Modern size ladder is all powers of two, so every board is
/// even-sided and this holds; the initializer asserts it.
public struct WrappedHexTopology: RectangularTopology {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        precondition(width > 0 && height > 0, "board must be non-empty")
        precondition(height % 2 == 0, "a hex torus needs an even height for consistent wrap")
        self.width = width
        self.height = height
    }

    public var cellCount: Int { width * height }

    public func neighbors(of c: Coord) -> [Coord] {
        // Parity is taken from the cell's own row (0..<height, since callers pass
        // on-board coords), matching HexTopology's offset tables.
        let offsets = (c.y & 1) == 0 ? HexTopology.evenRowOffsets : HexTopology.oddRowOffsets
        return offsets.compactMap { dx, dy in
            normalize(Coord(c.x + dx, c.y + dy))
        }
    }

    public func normalize(_ c: Coord) -> Coord? {
        // Euclidean modulo so negative coordinates wrap correctly.
        let nx = ((c.x % width) + width) % width
        let ny = ((c.y % height) + height) % height
        return Coord(nx, ny)
    }

    public func allCoords() -> AnySequence<Coord> {
        AnySequence { () -> AnyIterator<Coord> in
            var x = 0
            var y = 0
            return AnyIterator {
                guard y < self.height else { return nil }
                let coord = Coord(x, y)
                x += 1
                if x == self.width {
                    x = 0
                    y += 1
                }
                return coord
            }
        }
    }
}
