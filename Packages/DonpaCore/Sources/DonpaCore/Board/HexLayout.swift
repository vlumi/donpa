import CoreGraphics

/// Pointy-top hex layout in odd-r offset coordinates. `cellSize` is the horizontal
/// centre-to-centre spacing within a row (the hexagon's flat-to-flat width); odd
/// rows are shifted half a cell right, and rows are packed at 3/4 of the hexagon's
/// vertex-to-vertex height, i.e. a vertical pitch of `cellSize · √3/2`. Origin at
/// bottom-left, matching `SquareLayout` and SpriteKit's y-up convention.
public struct HexLayout: CellLayout {
    public let cellSize: CGFloat

    public var columnPitch: CGFloat { cellSize }
    public var rowPitch: CGFloat { cellSize * 0.866_025_403_784_438_6 }  // √3/2
    public var tileShape: TileShape { .pointyHex }
    /// Vertex-to-vertex height of one hexagon: 2/√3 of the flat-to-flat width.
    var vertexHeight: CGFloat { cellSize * 1.154_700_538_379_251_5 }
    // A pointy hex is `cellSize` wide (flat-to-flat) but 2/√3 taller (vertex-to-
    // vertex), so the sprite is that much taller than it is wide.
    public var tileSize: CGSize {
        CGSize(width: cellSize, height: vertexHeight)
    }

    public init(cellSize: CGFloat = 32) {
        self.cellSize = cellSize
    }

    /// Whether row `y` is shifted half a cell to the right (odd-r).
    static func isShifted(_ y: Int) -> Bool { (y & 1) != 0 }

    public func center(of c: Coord) -> CGPoint {
        let shift: CGFloat = Self.isShifted(c.y) ? 0.5 : 0
        // Row 0's centre sits half a VERTEX height up, so its bottom tips rest on
        // y = 0; rows then advance by the pitch. (y + 0.5)·pitch instead would park
        // the whole grid (vertexHeight − rowPitch)/2 ≈ 0.144·cellSize below its
        // declared box: row-0 tips at negative y — dead taps — and a low-skewed fit.
        return CGPoint(
            x: (CGFloat(c.x) + 0.5 + shift) * cellSize,
            y: CGFloat(c.y) * rowPitch + vertexHeight / 2
        )
    }

    public func coord(at p: CGPoint) -> Coord? {
        // The containing hex over the INFINITE tiling, nil when it's off-board
        // (negative). Clamping candidates to the board instead would snap a tap in
        // the notch beside an odd row's left edge — outside every real hex — onto a
        // cell the player never touched. Right/top overshoot returns out-of-range
        // coords, which the game layer's bounds guard drops (the SquareLayout
        // contract).
        let cell = nearestCell(to: p)
        guard cell.x >= 0, cell.y >= 0 else { return nil }
        return cell
    }

    public func unclampedCoord(at p: CGPoint) -> Coord {
        // For a wrapped hex board: return the nearest cell for ANY point, including
        // off-board (negative / past the edge) positions, so the caller can fold it
        // onto the torus with `normalize`. Parity math extends to negative rows
        // (two's-complement `&` keeps odd/even correct).
        nearestCell(to: p)
    }

    /// The hex whose centre is nearest `p`. A hex grid tiles the plane by nearest-
    /// centre (Voronoi = the hexagons), so that IS the containing cell. The true row
    /// is within ±1 of the naive estimate and the column within ±1 once the row
    /// offset is known, so test the 3×3 candidate block and keep the nearest centre.
    private func nearestCell(to p: CGPoint) -> Coord {
        let approxRow = Int(((p.y - vertexHeight / 2) / rowPitch).rounded())
        var best = Coord(0, 0)
        var bestDist = CGFloat.greatestFiniteMagnitude
        for dy in -1...1 {
            let y = approxRow + dy
            let shift: CGFloat = Self.isShifted(y) ? 0.5 : 0
            let approxCol = Int((p.x / cellSize - 0.5 - shift).rounded())
            for dx in -1...1 {
                let x = approxCol + dx
                let centre = center(of: Coord(x, y))
                let ddx = centre.x - p.x
                let ddy = centre.y - p.y
                let d = ddx * ddx + ddy * ddy
                if d < bestDist {
                    bestDist = d
                    best = Coord(x, y)
                }
            }
        }
        return best
    }

    public func boardSize(width: Int, height: Int) -> CGSize {
        // Odd rows push half a cell past the even-row right edge (when height > 1),
        // and the top/bottom rows only occupy 3/4 of their hex height each — the
        // last row adds one full hex height on top of the (h-1) row pitches.
        let extra: CGFloat = height > 1 ? 0.5 : 0
        return CGSize(
            width: (CGFloat(width) + extra) * cellSize,
            height: CGFloat(height - 1) * rowPitch + vertexHeight
        )
    }
}
