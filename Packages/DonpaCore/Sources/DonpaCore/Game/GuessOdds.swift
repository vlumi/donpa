import Foundation

/// Exact odds for a reveal made without certainty — the engine behind the
/// forced-guess ("luck") tracking.
///
/// Works strictly from player-visible information: the revealed numbers and the
/// total mine count. Player flags are ignored (they're marks, not facts); every
/// non-revealed cell is an unknown. The revealed numbers constrain the unknowns
/// next to them (the frontier); unknowns no number touches (the interior) share
/// whatever mines the frontier doesn't take, uniformly. Enumerating each frontier
/// component's consistent layouts and weighting by the interior's combinations
/// gives, for any cell, the exact fraction of layouts in which it is a mine.
///
/// Two facts fall out of the same enumeration:
/// - **survival** — P(the clicked cell is not a mine) at click time,
/// - **forced** — whether NO cell anywhere was certainly safe (a genuine guess,
///   not a choice; subsumes the classic solver deductions exactly).
///
/// Returns nil (no verdict, no tracking) rather than an estimate whenever the
/// position is out of bounds: boards past the analysis ceiling, a frontier
/// component too big to enumerate, or a blown step budget — the pathological
/// tail is dropped, never guessed at.
public enum GuessOdds {
    public struct Verdict: Sendable, Equatable {
        /// No certainly-safe cell existed anywhere — the player HAD to risk one.
        public let forced: Bool
        /// P(the clicked cell was not a mine), given everything visible.
        public let survival: Double
    }

    /// Analysis ceiling: boards up to XXL (256² cells). The per-reveal setup
    /// scans the whole board and indexes every unknown — ~5–10 ms off-main at
    /// XXL, harmless; on XXXL it would be 100 ms+ per click plus a second
    /// million-cell board copy held during analysis (the XXXL-CPU lesson), so
    /// the million-cell board alone sits out. (A locality-bounded sealed-pocket
    /// check could cover it later — the relaxed unresolvable rule is local.)
    public static let maxCells = 65_536
    /// A frontier component bigger than this is not enumerated (bail, nil).
    public static let maxComponentCells = 25
    /// Backtracking step budget per component (bail, nil).
    static let maxSteps = 2_000_000

    /// Analyze a reveal of `clicked` against the PRE-reveal `game` state.
    public static func analyze(_ game: Game, clicked: Coord) -> Verdict? {
        guard let clicked = game.board.topology.normalize(clicked),
            game.board[clicked].state == .hidden,
            let pos = position(for: game)
        else { return nil }
        let idx = pos.unknownIndex[clicked]!
        guard
            let v = verdict(
                clicked: idx, tallies: pos.tallies,
                interiorCount: pos.interiorCount, mines: pos.mines)
        else { return nil }
        // The relaxed half of "forced": a safe move may exist elsewhere, but if
        // this pocket can NEVER be resolved, the coin must be flipped eventually —
        // flipping it now counts (see isUnresolvable).
        if !v.forced, isUnresolvable(seeds: [idx], pos: pos, game: game) {
            return Verdict(forced: true, survival: v.survival)
        }
        return v
    }

    /// Analyze a CHORD at `c` against the PRE-chord state. A chord's gamble is
    /// the SET of cells it opens at once (the hidden, unflagged neighbours):
    /// survival = P(every one of them is safe). Flags are still not facts — they
    /// only pick which cells the chord opens, so a throwaway flag placed to avoid
    /// switching input modes makes the chord itself the guess being executed. A
    /// provably-safe set reads 1.0 (and a certain move elsewhere reads not-forced),
    /// exactly like a certain single reveal.
    public static func analyzeChord(_ game: Game, at c: Coord) -> Verdict? {
        guard let c = game.board.topology.normalize(c),
            game.board[c].state == .revealed
        else { return nil }
        let opened = game.board.topology.neighbors(of: c).filter {
            game.board[$0].state == .hidden
        }
        guard !opened.isEmpty, let pos = position(for: game) else { return nil }
        // Every opened cell neighbours `c`, whose constraint links them all into
        // one component.
        let openedIndices = Set(opened.map { pos.unknownIndex[$0]! })
        guard let v = chordVerdict(opened: openedIndices, pos: pos) else { return nil }
        if !v.forced, isUnresolvable(seeds: Array(openedIndices), pos: pos, game: game) {
            return Verdict(forced: true, survival: v.survival)
        }
        return v
    }

    /// The shared position prep: unknowns, constraints, components, and each
    /// component's enumerated layouts. nil past any bail-out.
    struct Position {
        var unknownIndex: [Coord: Int]
        var unknownCoords: [Coord]
        var tallies: [ComponentTally]
        var components: [Component]
        var interiorCount: Int
        var mines: Int
    }

    static func position(for game: Game) -> Position? {
        guard game.status == .playing else { return nil }  // first click is never a guess
        let board = game.board
        guard board.cellCount <= maxCells else { return nil }

        // Unknowns = every non-revealed cell (flags are player marks, not facts).
        var unknownIndex: [Coord: Int] = [:]
        var unknownCoords: [Coord] = []
        for c in board.allCoords where board[c].state != .revealed {
            unknownIndex[c] = unknownCoords.count
            unknownCoords.append(c)
        }
        let unknownCount = unknownCoords.count
        let mines = game.mineCount
        guard mines > 0, mines <= unknownCount else { return nil }

        // Constraints: each revealed number bounds the mines among its unknown
        // neighbours. (Revealed cells are never mines mid-game, so the number IS
        // the unknown-neighbour mine count.)
        var constraints: [(cells: [Int], count: Int)] = []
        for c in board.allCoords {
            let cell = board[c]
            guard cell.state == .revealed else { continue }
            let unknown = board.topology.neighbors(of: c).compactMap { unknownIndex[$0] }
            guard !unknown.isEmpty else { continue }
            constraints.append((cells: unknown, count: cell.adjacentMines))
        }

        // Frontier components: unknowns linked by shared constraints.
        let components = Self.components(unknownCount: unknownCount, constraints: constraints)
        let frontierCount = components.reduce(0) { $0 + $1.cells.count }
        let interiorCount = unknownCount - frontierCount

        // Enumerate each component's consistent layouts.
        var tallies: [ComponentTally] = []
        tallies.reserveCapacity(components.count)
        for component in components {
            guard component.cells.count <= maxComponentCells,
                let tally = enumerate(component: component),
                !tally.solutions.isEmpty
            else { return nil }
            tallies.append(tally)
        }

        return Position(
            unknownIndex: unknownIndex, unknownCoords: unknownCoords, tallies: tallies,
            components: components, interiorCount: interiorCount, mines: mines)
    }

    // MARK: - Frontier components

    struct Component {
        var cells: [Int]  // global unknown indices, discovery order
        var constraints: [(cells: [Int], count: Int)]  // cells as LOCAL indices
    }
    // MARK: - Component enumeration

    struct ComponentTally {
        var cells: [Int]  // global unknown indices
        /// solutions[m] = number of consistent layouts with m mines in the component.
        var solutions: [Int: Double]
        /// mineSolutions[local][m] = layouts with m mines where that cell is a mine.
        var mineSolutions: [[Int: Double]]
    }

    /// Enumerate a component's consistent layouts. `forcedSafe` (local indices)
    /// restricts to layouts where those cells hold no mine — the chord math. nil
    /// only past the step budget; an empty tally means no consistent layout.
    static func enumerate(
        component: Component, forcedSafe: Set<Int> = []
    ) -> ComponentTally? {
        let n = component.cells.count
        // Per-constraint running state for O(1) pruning per assignment.
        var needed = component.constraints.map(\.count)
        var remaining = component.constraints.map(\.cells.count)
        var byCell: [[Int]] = Array(repeating: [], count: n)
        for (i, constraint) in component.constraints.enumerated() {
            for cell in constraint.cells { byCell[cell].append(i) }
        }

        var isMine = Array(repeating: false, count: n)
        var solutions: [Int: Double] = [:]
        var mineSolutions: [[Int: Double]] = Array(repeating: [:], count: n)
        var steps = 0
        var overBudget = false

        func unplace(_ cell: Int, mine: Bool, placedInto count: Int) {
            for ci in byCell[cell].prefix(count) {
                remaining[ci] += 1
                if mine { needed[ci] += 1 }
            }
        }
        func recurse(_ cell: Int, minesSoFar: Int) {
            steps += 1
            if steps > maxSteps { overBudget = true }
            if overBudget { return }
            if cell == n {
                solutions[minesSoFar, default: 0] += 1
                for i in 0..<n where isMine[i] {
                    mineSolutions[i][minesSoFar, default: 0] += 1
                }
                return
            }
            for mine in (forcedSafe.contains(cell) ? [false] : [false, true]) {
                isMine[cell] = mine
                // The placement loop bails mid-way on violation; unwind exactly
                // what it did.
                var placed = 0
                var ok = true
                for ci in byCell[cell] {
                    remaining[ci] -= 1
                    if mine { needed[ci] -= 1 }
                    placed += 1
                    if needed[ci] < 0 || needed[ci] > remaining[ci] {
                        ok = false
                        break
                    }
                }
                if ok { recurse(cell + 1, minesSoFar: minesSoFar + (mine ? 1 : 0)) }
                unplace(cell, mine: mine, placedInto: placed)
            }
        }
        recurse(0, minesSoFar: 0)
        guard !overBudget else { return nil }
        return ComponentTally(
            cells: component.cells, solutions: solutions, mineSolutions: mineSolutions)
    }

    // MARK: - Combining components + interior

    private static func verdict(
        clicked: Int, tallies: [ComponentTally], interiorCount: Int, mines: Int
    ) -> Verdict? {
        // Everything below works in log space over non-negative counts, so a
        // finite value exists iff at least one real layout does — exact-zero
        // (certain safety) detection survives the floating point.
        // Log-space generating functions over "mines in this component".
        let logSolutions: [[Int: Double]] = tallies.map { tally in
            tally.solutions.mapValues { log($0) }
        }
        let convAll = convolve(logSolutions)

        // Total weight over all layouts.
        var logTotal = -Double.infinity
        for (s, w) in convAll {
            logTotal = logAdd(logTotal, w + logBinomial(interiorCount, mines - s))
        }
        guard logTotal > -.infinity else { return nil }  // inconsistent position

        let interior = interiorScan(convAll: convAll, interiorCount: interiorCount, mines: mines)
        let frontier = frontierScan(
            clicked: clicked, tallies: tallies, logSolutions: logSolutions,
            interiorCount: interiorCount, mines: mines)

        let interiorSafe = interiorCount > 0 && !interior.canHoldMines
        let forced = !frontier.anySafe && !interiorSafe

        let pMine: Double
        if let logClickedMine = frontier.logClickedMine {
            pMine = exp(logClickedMine - logTotal)
        } else {
            // Interior click: uniform share of the expected leftover.
            pMine =
                interior.canHoldMines
                ? exp(interior.logMines - logTotal) / Double(interiorCount)
                : 0
        }
        return Verdict(forced: forced, survival: max(0, min(1, 1 - pMine)))
    }

    /// Expected leftover mines in the interior (log space); safe iff the leftover
    /// is provably zero in every feasible layout.
    private static func interiorScan(
        convAll: [Int: Double], interiorCount: Int, mines: Int
    ) -> (logMines: Double, canHoldMines: Bool) {
        var logMines = -Double.infinity
        var canHold = false
        guard interiorCount > 0 else { return (logMines, canHold) }
        for (s, w) in convAll where mines - s >= 1 {
            let term = w + logBinomial(interiorCount, mines - s)
            guard term > -.infinity else { continue }
            canHold = true
            logMines = logAdd(logMines, term + log(Double(mines - s)))
        }
        return (logMines, canHold)
    }

    /// Per-frontier-cell mine weight: each component's mine-layouts convolved with
    /// the OTHERS' layouts and the interior. Reports whether any frontier cell is
    /// certainly safe, and the clicked cell's weight when it is a frontier cell
    /// (-inf = certainly safe; nil = the click was interior).
    private static func frontierScan(
        clicked: Int, tallies: [ComponentTally], logSolutions: [[Int: Double]],
        interiorCount: Int, mines: Int
    ) -> (anySafe: Bool, logClickedMine: Double?) {
        var anySafe = false
        var logClickedMine: Double?
        for (j, tally) in tallies.enumerated() {
            var others = logSolutions
            others.remove(at: j)
            let convOthers = convolve(others)
            for (local, global) in tally.cells.enumerated() {
                var logNum = -Double.infinity
                for (mj, count) in tally.mineSolutions[local] where count > 0 {
                    for (s, w) in convOthers {
                        logNum = logAdd(
                            logNum,
                            log(count) + w + logBinomial(interiorCount, mines - mj - s))
                    }
                }
                if logNum == -.infinity { anySafe = true }
                if global == clicked { logClickedMine = logNum }
            }
        }
        return (anySafe, logClickedMine)
    }

    /// The chord verdict: forced is the usual whole-board scan; survival is the
    /// weight of layouts where EVERY opened cell is safe, over the total — the
    /// opened component re-enumerated with those cells pinned safe.
    private static func chordVerdict(opened: Set<Int>, pos: Position) -> Verdict? {
        let logSolutions: [[Int: Double]] = pos.tallies.map { tally in
            tally.solutions.mapValues { log($0) }
        }
        let convAll = convolve(logSolutions)
        var logTotal = -Double.infinity
        for (s, w) in convAll {
            logTotal = logAdd(logTotal, w + logBinomial(pos.interiorCount, pos.mines - s))
        }
        guard logTotal > -.infinity else { return nil }

        let interior = interiorScan(
            convAll: convAll, interiorCount: pos.interiorCount, mines: pos.mines)
        let frontier = frontierScan(
            clicked: -1, tallies: pos.tallies, logSolutions: logSolutions,
            interiorCount: pos.interiorCount, mines: pos.mines)
        let interiorSafe = pos.interiorCount > 0 && !interior.canHoldMines
        let forced = !frontier.anySafe && !interiorSafe

        // Re-enumerate the opened cells' component with them pinned safe. (They
        // all neighbour the chorded number, so they share its constraint — one
        // component by construction.)
        guard let j = pos.tallies.firstIndex(where: { !opened.isDisjoint(with: $0.cells) })
        else { return nil }
        var local: [Int: Int] = [:]
        for (i, cell) in pos.components[j].cells.enumerated() { local[cell] = i }
        let forcedSafe = Set(opened.compactMap { local[$0] })
        guard forcedSafe.count == opened.count,  // all in one component, as constructed
            let safeTally = enumerate(component: pos.components[j], forcedSafe: forcedSafe)
        else { return nil }

        var safeSolutions = logSolutions
        safeSolutions[j] = safeTally.solutions.mapValues { log($0) }
        var logSafe = -Double.infinity
        for (s, w) in convolve(safeSolutions) {
            logSafe = logAdd(logSafe, w + logBinomial(pos.interiorCount, pos.mines - s))
        }
        let survival = logSafe > -.infinity ? exp(logSafe - logTotal) : 0
        return Verdict(forced: forced, survival: max(0, min(1, survival)))
    }

    /// Convolve log-space mine-count distributions: result[s] = log Σ Π counts.
    private static func convolve(_ parts: [[Int: Double]]) -> [Int: Double] {
        var acc: [Int: Double] = [0: 0]  // log(1) at zero mines
        for part in parts {
            var next: [Int: Double] = [:]
            for (s, w) in acc {
                for (m, v) in part {
                    let key = s + m
                    next[key] = logAdd(next[key] ?? -.infinity, w + v)
                }
            }
            acc = next
        }
        return acc
    }

    private static func logAdd(_ a: Double, _ b: Double) -> Double {
        if a == -.infinity { return b }
        if b == -.infinity { return a }
        let hi = max(a, b)
        return hi + log1p(exp(min(a, b) - hi))
    }

    private static func logBinomial(_ n: Int, _ k: Int) -> Double {
        guard k >= 0, k <= n else { return -.infinity }
        return lgamma(Double(n + 1)) - lgamma(Double(k + 1)) - lgamma(Double(n - k + 1))
    }
}

// Split from the enum body for the type-length budget.
extension GuessOdds {

    static func components(
        unknownCount: Int, constraints: [(cells: [Int], count: Int)]
    ) -> [Component] {
        // Map each frontier cell to its constraints, then BFS over shared membership.
        var byCell: [[Int]] = Array(repeating: [], count: unknownCount)
        for (i, constraint) in constraints.enumerated() {
            for cell in constraint.cells { byCell[cell].append(i) }
        }
        var cellSeen = Array(repeating: false, count: unknownCount)
        var constraintSeen = Array(repeating: false, count: constraints.count)
        var out: [Component] = []
        for start in 0..<unknownCount where !byCell[start].isEmpty && !cellSeen[start] {
            var cells: [Int] = []
            var members: [Int] = []
            var queue = [start]
            cellSeen[start] = true
            while let cell = queue.popLast() {
                cells.append(cell)
                for ci in byCell[cell] where !constraintSeen[ci] {
                    constraintSeen[ci] = true
                    members.append(ci)
                    for next in constraints[ci].cells where !cellSeen[next] {
                        cellSeen[next] = true
                        queue.append(next)
                    }
                }
            }
            var local: [Int: Int] = [:]
            for (i, cell) in cells.enumerated() { local[cell] = i }
            let localConstraints = members.map { ci in
                (cells: constraints[ci].cells.map { local[$0]! }, count: constraints[ci].count)
            }
            out.append(Component(cells: cells, constraints: localConstraints))
        }
        return out
    }
}
