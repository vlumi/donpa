public enum GameStatus: String, Sendable, Equatable, Codable {
    case notStarted
    case playing
    case won
    case lost

    public var isLive: Bool { self == .notStarted || self == .playing }
    public var isFinished: Bool { self == .won || self == .lost }
    public var isPlaying: Bool { self == .playing }
}

/// The rules engine. Geometry-agnostic — all neighbour questions go through
/// `Topology` (via `Board`).
public struct Game: Sendable {
    public private(set) var board: Board
    public private(set) var status: GameStatus = .notStarted
    public let mineCount: Int

    /// Non-mine cells revealed, tracked incrementally so win detection is O(1).
    public private(set) var revealedSafeCount: Int = 0

    public var safeCellCount: Int { board.cellCount - mineCount }

    /// O(1) fingerprint of player-visible state, changed by every mutation —
    /// compare before/after to detect a no-op reveal/chord and skip the
    /// expensive redraw/autosave/minimap rebuild.
    public var changeToken: Int {
        var h = Hasher()
        h.combine(revealedSafeCount)
        h.combine(board.flagCount)
        h.combine(status)
        return h.finalize()
    }

    /// Fraction of safe cells revealed, 0...1.
    public var progress: Double {
        let safe = safeCellCount
        return safe > 0 ? Double(revealedSafeCount) / Double(safe) : 0
    }

    /// The cell whose reveal detonated on a loss (even via a chord); nil unless lost.
    public private(set) var lossCoord: Coord?

    private let topology: any RectangularTopology
    private var minesPlaced = false

    /// How the first click arms the board. `.noGuess` (Drills) generates a
    /// verified no-guess layout, falling back to standard if the generator gives up.
    public enum MinePlacement: Sendable { case standard, noGuess }
    public private(set) var placement: MinePlacement = .standard

    public init(difficulty: Difficulty) {
        let topology = BoundedSquareTopology(width: difficulty.width, height: difficulty.height)
        self.topology = topology
        self.board = Board(topology: topology)
        self.mineCount = difficulty.mineCount
    }

    public init(config: GameConfig) {
        self.topology = config.topology
        self.board = Board(topology: config.topology)
        self.mineCount = config.mineCount
        self.placement = config.family == .practice ? .noGuess : .standard
    }

    public init(topology: any RectangularTopology, mineCount: Int) {
        self.topology = topology
        self.board = Board(topology: topology)
        self.mineCount = mineCount
    }

    /// Test seam: mines pre-placed, as if the first click had happened.
    init(topology: any RectangularTopology, mines: Set<Coord>) {
        self.topology = topology
        var board = Board(topology: topology)
        board.placeMines(at: mines)
        self.board = board
        self.mineCount = mines.count
        self.minesPlaced = true
        self.status = .playing
    }

    public static func restored(from s: GameSnapshot) -> Game {
        // Trust the SAVED layout's count over the config's freshly-computed one:
        // the config is symbolic, and a density retune between builds would
        // otherwise skew win detection against the actual mines.
        let mineCount = s.mines.isEmpty ? s.config.mineCount : s.mines.count
        var game = Game(topology: s.config.topology, mineCount: mineCount)
        game.board.restore(
            mines: s.mines, revealed: s.revealed, flagged: s.flagged, questioned: s.questioned)
        game.minesPlaced = !game.board.mineCoords.isEmpty
        game.status = s.status
        // Derive from the restored board, not the saved number, so a tampered
        // save can't skew progress or win detection.
        game.revealedSafeCount = game.board.revealedSafeCount
        game.lossCoord = s.lossCoord
        return game
    }

    public var flagsRemaining: Int { mineCount - board.flagCount }

    // MARK: - Reveal

    /// Reveals `c`. On the first reveal, mines are placed avoiding `c` and its
    /// neighbours, guaranteeing a 0-opening.
    public mutating func reveal(_ c: Coord) {
        var rng = SystemRandomNumberGenerator()
        reveal(c, using: &rng)
    }

    mutating func moveMineForGeneration(from old: Coord, to new: Coord) {
        board.moveMine(from: old, to: new)
    }

    /// A verified no-guess layout, or a plain safe-zone layout when the
    /// generator gives up.
    static func noGuessMines<R: RandomNumberGenerator>(
        topology: any RectangularTopology, mineCount: Int, firstClick: Coord, using rng: inout R
    ) -> Set<Coord> {
        PracticeBoard.mines(
            topology: topology, mineCount: mineCount, firstClick: firstClick, using: &rng)
            ?? MinePlacer.placeMines(
                topology: topology, mineCount: mineCount, firstClick: firstClick, using: &rng)
    }

    /// Arm the board before the first click is known: all mines, NO safe zone —
    /// the first reveal relocates any under it. No-op on an armed board, and on
    /// `.noGuess` (that layout needs the first click).
    public mutating func placeMinesEagerly<R: RandomNumberGenerator>(using rng: inout R) {
        guard !minesPlaced, placement == .standard else { return }
        let mines = MinePlacer.randomMines(topology: topology, mineCount: mineCount, using: &rng)
        board.placeMines(at: mines)
        minesPlaced = true
    }

    public mutating func reveal<R: RandomNumberGenerator>(_ c: Coord, using rng: inout R) {
        guard status.isLive else { return }
        // Shadow with the FOLDED coord: past this point the raw coord would
        // read/write phantom off-board cells on a wrapped topology. Bounded
        // topologies still reject off-board here.
        guard let c = topology.normalize(c) else { return }
        // A "?" is diggable; only a flag protects a cell.
        guard board[c].state == .hidden || board[c].state == .questioned else { return }

        if !minesPlaced {
            let mines: Set<Coord>
            switch placement {
            case .standard:
                mines = MinePlacer.placeMines(
                    topology: topology, mineCount: mineCount, firstClick: c, using: &rng)
            case .noGuess:
                mines = Self.noGuessMines(
                    topology: topology, mineCount: mineCount, firstClick: c, using: &rng)
            }
            board.placeMines(at: mines)
            minesPlaced = true
            status = .playing
        } else if status == .notStarted {
            // Pre-armed with no safe zone: clear the click's neighbourhood now.
            var safeZone: Set<Coord> = [c]
            safeZone.formUnion(topology.neighbors(of: c))
            board.relocateMines(outOf: safeZone, using: &rng)
            status = .playing
        }

        if board[c].isMine {
            board[c].state = .revealed
            status = .lost
            lossCoord = c
            revealAllMines()
            return
        }

        floodFill(from: c)
        checkWin()
    }

    /// Iterative flood fill, expanding only out of 0-cells. A "?" is swept like
    /// a hidden cell — only a flag blocks the cascade.
    private mutating func floodFill(from start: Coord) {
        var queue = [start]
        var enqueued: Set<Coord> = [start]

        while let c = queue.popLast() {
            board[c].state = .revealed
            revealedSafeCount += 1  // flood-fill only ever reveals non-mine cells
            guard board[c].adjacentMines == 0 else { continue }
            for n in topology.neighbors(of: c) where !enqueued.contains(n) {
                let s = board[n].state
                guard s == .hidden || s == .questioned, !board[n].isMine else { continue }
                enqueued.insert(n)
                queue.append(n)
            }
        }
    }

    // MARK: - Flagging

    /// Advance a cell's mark: hidden → flagged → "?" → hidden with
    /// `useQuestionMarks`, else the plain toggle. A "?" never counts as a flag.
    public mutating func toggleFlag(_ c: Coord, useQuestionMarks: Bool = false) {
        guard status.isLive else { return }
        // Folded coord, same as `reveal`.
        guard let c = topology.normalize(c) else { return }
        switch board[c].state {
        case .hidden: board[c].state = .flagged
        case .flagged: board[c].state = useQuestionMarks ? .questioned : .hidden
        case .questioned: board[c].state = .hidden
        case .revealed: break
        }
    }

    // MARK: - Chord

    /// If `c` is a revealed number whose adjacent flag count equals its number,
    /// reveal all its non-flagged neighbours. Mis-flagging can lose the game.
    public mutating func chord(_ c: Coord) {
        var rng = SystemRandomNumberGenerator()
        chord(c, using: &rng)
    }

    public mutating func chord<R: RandomNumberGenerator>(_ c: Coord, using rng: inout R) {
        guard status == .playing else { return }
        guard board[c].state == .revealed, board[c].adjacentMines > 0 else { return }
        let neighbors = topology.neighbors(of: c)
        let flagged = neighbors.filter { board[$0].state == .flagged }.count
        guard flagged == board[c].adjacentMines else { return }
        // A "?" doesn't protect: a chord opens it like a hidden cell.
        for n in neighbors where board[n].state == .hidden || board[n].state == .questioned {
            reveal(n, using: &rng)
            if status == .lost { return }
        }
    }

    /// Whether a chord on `c` would actually reveal something. The UI routes
    /// EVERY tap on a revealed cell through `chord`; callers use this to skip
    /// the compute and the chord stats for no-op taps.
    public func canChord(_ c: Coord) -> Bool {
        guard status == .playing else { return false }
        guard board[c].state == .revealed, board[c].adjacentMines > 0 else { return false }
        let neighbors = topology.neighbors(of: c)
        guard neighbors.contains(where: { board[$0].state == .hidden }) else { return false }
        return neighbors.filter { board[$0].state == .flagged }.count == board[c].adjacentMines
    }

    // MARK: - Win/lose helpers

    private mutating func checkWin() {
        guard revealedSafeCount == safeCellCount else { return }
        status = .won
        flagAllMines()
    }

    private mutating func revealAllMines() {
        // Leave flagged mines flagged: revealing them would make `flagsRemaining`
        // jump back up after a loss.
        for c in board.mineCoords where board[c].state != .flagged {
            board[c].state = .revealed
        }
    }

    private mutating func flagAllMines() {
        for c in board.mineCoords {
            board[c].state = .flagged
        }
    }
}
