/// Per-cell visibility state.
public enum CellState: Sendable {
    case hidden
    case revealed
    case flagged
}

/// One cell, bit-packed into a single byte — `state` (2 bits), `isMine` (1 bit),
/// `adjacentMines` (4 bits, 0…8). On a 1024² board this is a 1MB cell array vs
/// 16MB unpacked, so the per-move COW copy is ~16× cheaper.
public struct Cell: Sendable {
    private var bits: UInt8 = 0  // [ adjacent:4 | mine:1 | state:2 ], bit 7 unused

    public init() {}

    public var state: CellState {
        get {
            switch bits & 0b11 {
            case 1: return .revealed
            case 2: return .flagged
            default: return .hidden
            }
        }
        set {
            let code: UInt8
            switch newValue {
            case .hidden: code = 0
            case .revealed: code = 1
            case .flagged: code = 2
            }
            bits = (bits & ~0b11) | code
        }
    }

    public var isMine: Bool {
        get { bits & 0b100 != 0 }
        set { bits = newValue ? (bits | 0b100) : (bits & ~0b100) }
    }

    /// Number of mines among this cell's neighbours. Valid once mines are placed.
    public var adjacentMines: Int {
        get { Int(bits >> 3) }
        set { bits = (bits & 0b111) | (UInt8(newValue) << 3) }
    }
}

/// Dense flat cell storage for a rectangular board — `index = y·width + x`, the
/// memory/speed path for huge boards. Get returns a default `Cell` for an
/// off-board coord; set ignores it.
///
/// Must be a **struct holding the array directly**, so a write mutates in place
/// via COW. An enum case would force `self = .flat(cells, …)` on every write,
/// un-uniquing the array and copying all N cells → O(n²) (measured: 27s vs ~0.5s
/// for a 500² placeMines).
private struct CellStore: Sendable {
    private var cells: [Cell]
    private let rect: any RectangularTopology

    init(topology: any RectangularTopology) {
        self.rect = topology
        self.cells = Array(repeating: Cell(), count: topology.cellCount)
    }

    subscript(_ c: Coord) -> Cell {
        get {
            guard let i = rect.index(of: c) else { return Cell() }
            return cells[i]
        }
        set {
            // `cells` is uniquely referenced here, so COW mutates in place — O(1).
            guard let i = rect.index(of: c) else { return }
            cells[i] = newValue
        }
    }

    /// All (coord, cell) pairs — for the persistence/derived accessors.
    ///
    /// Hot path on a 1M-cell board, so it avoids two per-cell costs the profiler
    /// caught: (1) `rect.coord(at:)` drags the heap-allocated `any RectangularTopology`
    /// existential through ARC every iteration — instead capture the plain `Int` width
    /// and compute `x,y` arithmetically (the store is dense row-major); (2) reading
    /// `cells[i]` retains the array buffer per access — instead walk one
    /// `withUnsafeBufferPointer` so the loop is pure value reads, zero ARC. (Debug
    /// shows this as a `swift_retain`/`swift_release` storm; release elides most, but
    /// the work is real on a weak CPU.)
    func forEach(_ body: (Coord, Cell) -> Void) {
        let w = rect.width
        cells.withUnsafeBufferPointer { buf in
            for i in buf.indices { body(Coord(i % w, i / w), buf[i]) }
        }
    }

    /// Row-major cells, yielded by flat index only — no per-cell `coord(at:)`
    /// topology round-trip. For bulk scans (e.g. the minimap raster) where the
    /// caller derives x,y from the index itself (`x = i % width`, `y = i / width`).
    /// `withUnsafeBufferPointer` so the loop is pure value reads with no per-cell ARC.
    func forEachIndexed(_ body: (Int, Cell) -> Void) {
        cells.withUnsafeBufferPointer { buf in
            for i in buf.indices { body(i, buf[i]) }
        }
    }
}

/// The grid of cells plus the mine layout, indexed by `Coord`.
///
/// Holds *what* is in each cell and recomputes adjacency, but no game rules
/// (those live in `Game`). Neighbour questions go to the injected `Topology`, so
/// it's geometry-agnostic; cells live in a flat row-major array (see `CellStore`).
public struct Board: Sendable {
    public let topology: any RectangularTopology
    private var cells: CellStore

    /// Mine coordinates, set once in `placeMines`. Kept as a set so end-game paths
    /// iterate only the mines (~130k) rather than scanning every cell (1M).
    private var minePositions: Set<Coord> = []
    public private(set) var mineCount: Int = 0
    /// Maintained incrementally — all cell mutation funnels through the subscript.
    public private(set) var flagCount: Int = 0

    public init(topology: any RectangularTopology) {
        self.topology = topology
        self.cells = CellStore(topology: topology)
    }

    public subscript(_ c: Coord) -> Cell {
        get { cells[c] }
        set {
            // Keep flagCount in step with any state change.
            let was = cells[c].state
            if was != newValue.state {
                if was == .flagged { flagCount -= 1 }
                if newValue.state == .flagged { flagCount += 1 }
            }
            cells[c] = newValue
        }
    }

    public var allCoords: AnySequence<Coord> { topology.allCoords() }
    public var cellCount: Int { topology.cellCount }

    /// Coordinate sets for persistence — compact vs encoding the full cell dict.
    public var mineCoords: Set<Coord> { minePositions }
    public var revealedCoords: Set<Coord> { coords { $0.state == .revealed } }
    public var flaggedCoords: Set<Coord> { coords { $0.state == .flagged } }

    /// Mines that are correctly flagged ("disarmed"). Iterates only the mine set.
    public var disarmedMineCount: Int {
        minePositions.reduce(0) { $0 + (cells[$1].state == .flagged ? 1 : 0) }
    }

    /// Revealed non-mine cells, derived from the board so a restored game can
    /// recompute it rather than trust a persisted number.
    public var revealedSafeCount: Int { coords { $0.state == .revealed && !$0.isMine }.count }

    /// Whether a revealed number has MORE flags around it than its value — a
    /// guaranteed mistake (a cell can't border more mines than its count). Surfaced
    /// as a passive error cue: it marks the impossible number, not which flag is
    /// wrong, so it catches a slip without solving anything. False for hidden,
    /// flagged, mine, or 0 cells (nothing to over-flag). O(neighbours) — local, so a
    /// flag toggle only need re-check the toggled cell's neighbourhood.
    public func isOverFlagged(_ c: Coord) -> Bool {
        let cell = self[c]
        guard cell.state == .revealed, !cell.isMine, cell.adjacentMines > 0 else { return false }
        var flags = 0
        for n in topology.neighbors(of: c) where self[n].state == .flagged {
            flags += 1
        }
        return flags > cell.adjacentMines
    }

    private func coords(where match: (Cell) -> Bool) -> Set<Coord> {
        var result: Set<Coord> = []
        cells.forEach { c, cell in if match(cell) { result.insert(c) } }
        return result
    }

    /// Visit every cell in row-major order, yielding only its flat index — the fast
    /// path for whole-board scans (no `Coord` allocation, no topology `index(of:)`
    /// per cell). The board is dense row-major, so `x = i % width`, `y = i / width`.
    /// This is what makes the XXXL (1M-cell) minimap raster tractable.
    public func forEachCellIndexed(_ body: (Int, Cell) -> Void) {
        cells.forEachIndexed(body)
    }

    /// Rebuild a board from a saved layout without re-randomizing the (first-click-
    /// safe) mines. Coords are filtered to in-bounds, so a tampered save with
    /// off-board coords yields an odd-but-valid board, never a broken one.
    public mutating func restore(mines: Set<Coord>, revealed: Set<Coord>, flagged: Set<Coord>) {
        let onBoard = Set(topology.allCoords())
        placeMines(at: mines.intersection(onBoard))
        for c in revealed where onBoard.contains(c) { self[c].state = .revealed }
        for c in flagged where onBoard.contains(c) { self[c].state = .flagged }
    }

    /// Places mines and recomputes adjacency, iterating only the MINES (cost scales
    /// with mine count, not cell count). Adjacency is *scattered* outward — each
    /// mine bumps its neighbours — turning an N×8 scan into mines×8.
    ///
    /// Assumes a clean board (no reset pass); only ever called once per board.
    public mutating func placeMines(at mineCoords: Set<Coord>) {
        minePositions = mineCoords
        mineCount = mineCoords.count
        for c in mineCoords {
            cells[c].isMine = true
            for n in topology.neighbors(of: c) {
                cells[n].adjacentMines += 1
            }
        }
    }

    /// Move any mines inside `safeZone` to random cells outside it, fixing
    /// adjacency locally — so a board pre-armed before the first click can still
    /// guarantee a clear opening. Touches only the moved mines and their
    /// neighbours, so it's the cheap O(1)-ish fix-up on the first tap.
    public mutating func relocateMines<R: RandomNumberGenerator>(
        outOf safeZone: Set<Coord>, using rng: inout R
    ) {
        let toMove = minePositions.intersection(safeZone)
        guard !toMove.isEmpty else { return }
        let cellCount = topology.cellCount
        for old in toMove {
            // Remove the mine at `old`.
            cells[old].isMine = false
            for n in topology.neighbors(of: old) { cells[n].adjacentMines -= 1 }
            minePositions.remove(old)
            // Find a fresh home: a non-safe, currently-mine-free cell.
            var new = topology.coord(at: Int.random(in: 0..<cellCount, using: &rng))
            while safeZone.contains(new) || cells[new].isMine || new == old {
                new = topology.coord(at: Int.random(in: 0..<cellCount, using: &rng))
            }
            cells[new].isMine = true
            for n in topology.neighbors(of: new) { cells[n].adjacentMines += 1 }
            minePositions.insert(new)
        }
    }
}
