/// A logical Minesweeper solver: plays a `Game` using only player-visible
/// information (revealed numbers and its own flags), never the hidden mine
/// layout. Applies the two classic single-constraint deductions to a fixpoint:
///
///   1. **All-mines:** number == hidden-neighbour count → flag them all.
///   2. **All-clear:** number == flagged-neighbour count → reveal the rest.
///
/// When neither makes progress, the position requires a guess. Single-constraint
/// logic only (no CSP) — the standard baseline for measuring guess-dependence.
public struct Solver {
    public struct Result: Sendable, Equatable {
        /// True if the game reached `.won` using only the two deduction rules.
        public var solvedWithoutGuessing: Bool
        /// Number of deduction steps (cells revealed or flagged by logic).
        public var deductions: Int
        /// Cells revealed by the very first click's flood-fill (the opening).
        public var firstOpenSize: Int
        /// Final game status when the solver stopped.
        public var status: GameStatus
    }

    public init() {}

    /// Play `game` to completion-or-stuck from `firstClick`, using deductions
    /// only. `game` should be freshly started (not yet revealed); mines are
    /// placed by the first reveal via the injected RNG, exactly as in real play.
    public func solve<R: RandomNumberGenerator>(
        _ game: inout Game, firstClick: Coord, using rng: inout R
    ) -> Result {
        game.reveal(firstClick, using: &rng)
        return run(&game, seeds: [firstClick], firstOpenSize: revealedCount(in: game), using: &rng)
            .result
    }

    /// The generator's entry points: like `solve`/resume, but also reporting the
    /// STUCK NUMBERS the run ended on (revealed numbers that still see hidden
    /// cells but can't fire either rule) — the repair loop's exact work list,
    /// so it never scans the board for them.
    func solveTracked<R: RandomNumberGenerator>(
        _ game: inout Game, firstClick: Coord, using rng: inout R
    ) -> (result: Result, stuckNumbers: [Coord]) {
        game.reveal(firstClick, using: &rng)
        return run(&game, seeds: [firstClick], firstOpenSize: revealedCount(in: game), using: &rng)
    }

    /// Resume deduction on an in-progress board, examining only what `seeds`
    /// can reach — the repair loop continues from exactly the numbers its
    /// relocations changed, keeping total work linear instead of re-solving
    /// from scratch every round. (`firstOpenSize` reads 0 on a resume — there
    /// is no opening flood to measure.)
    func continueTracked<R: RandomNumberGenerator>(
        _ game: inout Game, from seeds: [Coord], using rng: inout R
    ) -> (result: Result, stuckNumbers: [Coord]) {
        run(&game, seeds: seeds, firstOpenSize: 0, using: &rng)
    }

    /// The worklist state — not full-board rescans: the single-constraint
    /// fixpoint is confluent, so examining only numbers whose neighbourhood
    /// CHANGED reaches the same end state in O(changes). (The rescan version
    /// cost O(board) per pass, seconds-per-solve on a million cells — and the
    /// no-guess generator resumes per repair round, so this matters.)
    private struct Worklist {
        var queue: [Coord] = []
        var queued = Set<Coord>()
        var absorbed = Set<Coord>()

        /// Examine `c` (again) later, if it's a number at all.
        mutating func enqueue(_ c: Coord, in game: Game) {
            guard game.board[c].state == .revealed, game.board[c].adjacentMines > 0,
                queued.insert(c).inserted
            else { return }
            queue.append(c)
        }

        /// Walk a just-revealed region from `start` (a flood is zeros + their
        /// numbered fringe), enqueueing every number that can now see something
        /// new — the fringe itself, plus old numbers bordering the region (they
        /// just lost hidden neighbours).
        mutating func absorb(from start: Coord, in game: Game) {
            var stack = [start]
            while let v = stack.popLast() {
                guard game.board[v].state == .revealed, absorbed.insert(v).inserted
                else { continue }
                let neighbours = game.board.topology.neighbors(of: v)
                if game.board[v].adjacentMines > 0 {
                    enqueue(v, in: game)
                } else {
                    for n in neighbours where game.board[n].state == .revealed {
                        stack.append(n)
                    }
                }
                for n in neighbours { enqueue(n, in: game) }
            }
        }
    }

    private func run<R: RandomNumberGenerator>(
        _ game: inout Game, seeds: [Coord], firstOpenSize firstOpen: Int, using rng: inout R
    ) -> (result: Result, stuckNumbers: [Coord]) {
        var deductions = 0
        var unresolved = Set<Coord>()
        var work = Worklist()
        for seed in seeds { work.absorb(from: seed, in: game) }

        while game.status == .playing, let c = work.queue.popLast() {
            work.queued.remove(c)
            unresolved.remove(c)  // being re-examined; re-inserted below if still stuck
            let cell = game.board[c]
            guard cell.state == .revealed, cell.adjacentMines > 0 else { continue }
            let neighbours = game.board.topology.neighbors(of: c)
            let hidden = neighbours.filter { game.board[$0].state == .hidden }
            guard !hidden.isEmpty else { continue }
            let flagged = neighbours.filter { game.board[$0].state == .flagged }.count

            if cell.adjacentMines - flagged == hidden.count {
                // Rule 1: remaining mines exactly fill the hidden neighbours.
                for h in hidden {
                    game.toggleFlag(h)
                    deductions += 1
                    for n in game.board.topology.neighbors(of: h) { work.enqueue(n, in: game) }
                }
            } else if cell.adjacentMines == flagged {
                // Rule 2: all mines accounted for → the rest are safe.
                for h in hidden where game.board[h].state == .hidden {
                    game.reveal(h, using: &rng)
                    deductions += 1
                    if game.status == .lost {  // a wrong flag elsewhere
                        let result = Result(
                            solvedWithoutGuessing: false, deductions: deductions,
                            firstOpenSize: firstOpen, status: game.status)
                        return (result, [])
                    }
                    work.absorb(from: h, in: game)
                }
            } else {
                // Neither rule fires: park it — any neighbour change re-enqueues
                // it, and whatever is still parked at the end IS the stuck front.
                unresolved.insert(c)
            }
        }

        let result = Result(
            solvedWithoutGuessing: game.status == .won,
            deductions: deductions,
            firstOpenSize: firstOpen,
            status: game.status)
        return (result, game.status == .playing ? Array(unresolved) : [])
    }

    private func revealedCount(in game: Game) -> Int {
        game.board.allCoords.reduce(0) { $0 + (game.board[$1].state == .revealed ? 1 : 0) }
    }
}
