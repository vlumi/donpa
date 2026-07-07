import Foundation

/// The relaxed half of "forced" (user rule, 2026-07-07): a certainly-safe move
/// existing SOMEWHERE doesn't make a guess optional when the pocket being
/// gambled on can never be resolved. A pocket is unresolvable when it is
///
/// - **sealed** — every pocket cell's neighbours are revealed, in the pocket, or
///   provably mines, so no future reveal can ever put a new number next to it —
/// - and **rigid** — every consistent layout puts the same number of mines in
///   it, so not even the endgame mine counter can squeeze it.
///
/// Then no information about the pocket will ever arrive: you could clear the
/// whole rest of the board and face the exact same coin. Deferring it is pure
/// waste, so flipping it early counts as forced (at the pocket's odds, which by
/// rigidity are its odds forever).
///
/// Certainty here is read from the unfiltered enumeration aggregates — a cell
/// that is a mine in every enumerated layout is one in every feasible layout,
/// so the check errs toward "resolvable" (records nothing), never the reverse.
extension GuessOdds {
    /// Per-cell certainty and component membership, off the aggregates.
    fileprivate struct Census {
        var certainMine = Set<Int>()
        var certainSafe = Set<Int>()
        var membership: [Int: (comp: Int, local: Int)] = [:]

        init(_ pos: Position) {
            for (j, tally) in pos.tallies.enumerated() {
                let total = tally.solutions.values.reduce(0, +)
                for (local, global) in tally.cells.enumerated() {
                    membership[global] = (j, local)
                    let mines = tally.mineSolutions[local].values.reduce(0, +)
                    if mines == total { certainMine.insert(global) }
                    if mines == 0 { certainSafe.insert(global) }
                }
            }
        }
    }

    /// Whether the pocket containing `seeds` (the clicked cell, or a chord's
    /// opened set) can never be resolved by safe play.
    static func isUnresolvable(seeds: [Int], pos: Position, game: Game) -> Bool {
        let census = Census(pos)

        // A certain-mine seed is suicide, not a gamble; certain-safe seeds are no
        // gamble at all and drop out (a chord can mix them with real risks).
        guard !seeds.contains(where: { census.certainMine.contains($0) }) else { return false }
        let uncertain = seeds.filter { !census.certainSafe.contains($0) }
        guard !uncertain.isEmpty else { return false }

        if uncertain.contains(where: { census.membership[$0] == nil }) {
            guard uncertain.allSatisfy({ census.membership[$0] == nil }) else { return false }
            return interiorUnresolvable(census: census, pos: pos, game: game)
        }
        return frontierUnresolvable(
            seeds: uncertain, census: census, pos: pos, game: game)
    }

    /// Interior cells are exchangeable, so the pocket is the whole interior.
    /// Rigid iff every component's mine count is fixed (then the leftover is
    /// too) — and the fixed leftover must be a real gamble: zero mines means
    /// certain-safe territory, all-mines means suicide.
    private static func interiorUnresolvable(census: Census, pos: Position, game: Game) -> Bool {
        guard pos.tallies.allSatisfy({ $0.solutions.count == 1 }) else { return false }
        let interior = (0..<pos.unknownCoords.count).filter { census.membership[$0] == nil }
        let leftover = pos.mines - pos.tallies.reduce(0) { $0 + ($1.solutions.keys.first ?? 0) }
        guard leftover > 0, leftover < interior.count else { return false }
        return sealed(pocket: Set(interior), certainMine: census.certainMine, pos: pos, game: game)
    }

    /// Frontier seeds: all must share one component (a chord's opened set does by
    /// construction); flood the pocket over uncertain cells sharing a constraint,
    /// then check sealed + rigid.
    private static func frontierUnresolvable(
        seeds: [Int], census: Census, pos: Position, game: Game
    ) -> Bool {
        unresolvablePocket(seeds: seeds, census: census, pos: pos, game: game) != nil
    }

    /// The sealed, rigid pocket around frontier seeds — with its residual
    /// enumeration, because rigidity makes the global weighting flat across the
    /// pocket's layouts, so this tally alone yields EXACT odds (the huge-board
    /// path leans on that). nil when the pocket is resolvable.
    fileprivate static func unresolvablePocket(
        seeds: [Int], census: Census, pos: Position, game: Game
    ) -> (component: Component, tally: ComponentTally)? {
        guard let comp = census.membership[seeds[0]]?.comp,
            seeds.allSatisfy({ census.membership[$0]?.comp == comp })
        else { return nil }
        let component = pos.components[comp]
        let certainLocal = Set(
            component.cells.indices.filter { census.certainMine.contains(component.cells[$0]) })

        var pocket = Set(seeds.compactMap { census.membership[$0].map(\.local) })
        var queue = Array(pocket)
        while let cell = queue.popLast() {
            for constraint in component.constraints where constraint.cells.contains(cell) {
                for next in constraint.cells
                where !pocket.contains(next) && !certainLocal.contains(next) {
                    pocket.insert(next)
                    queue.append(next)
                }
            }
        }

        let pocketGlobal = Set(pocket.map { component.cells[$0] })
        guard sealed(pocket: pocketGlobal, certainMine: census.certainMine, pos: pos, game: game)
        else { return nil }

        // Rigid: re-enumerate just the pocket under its residual constraints
        // (certain mines already subtracted) — one mine count across all layouts?
        var local: [Int: Int] = [:]
        let pocketCells = Array(pocket)
        for (i, cell) in pocketCells.enumerated() { local[cell] = i }
        let residual = component.constraints.compactMap {
            residualConstraint($0, local: local, certainLocal: certainLocal)
        }
        let pocketComponent = Component(
            cells: pocketCells.map { component.cells[$0] }, constraints: residual)
        guard let tally = enumerate(component: pocketComponent), tally.solutions.count == 1
        else { return nil }
        return (pocketComponent, tally)
    }

    /// A constraint restricted to the pocket: its pocket cells (pocket-local
    /// indices) and its count minus the certain mines it already touches.
    private static func residualConstraint(
        _ constraint: (cells: [Int], count: Int), local: [Int: Int], certainLocal: Set<Int>
    ) -> (cells: [Int], count: Int)? {
        let cells = constraint.cells.compactMap { local[$0] }
        guard !cells.isEmpty else { return nil }
        let pinned = constraint.cells.filter { certainLocal.contains($0) }.count
        return (cells: cells, count: constraint.count - pinned)
    }

    /// No future number can ever see into the pocket: every pocket cell's
    /// neighbours are revealed, in the pocket, or provably mines (a provable mine
    /// never becomes a number). Any other unknown neighbour — including a merely
    /// player-flagged one — could one day carry a constraint into the pocket.
    /// Reads revealed-ness off the BOARD, not the index: a local (huge-board)
    /// position only indexes its own component, and an unindexed wilderness
    /// neighbour must read as unknown, not revealed.
    private static func sealed(
        pocket: Set<Int>, certainMine: Set<Int>, pos: Position, game: Game
    ) -> Bool {
        for cell in pocket {
            for nbr in game.board.topology.neighbors(of: pos.unknownCoords[cell]) {
                guard game.board[nbr].state != .revealed else { continue }
                guard let idx = pos.unknownIndex[nbr],
                    pocket.contains(idx) || certainMine.contains(idx)
                else { return false }
            }
        }
        return true
    }
}

// MARK: - The huge-board path

/// Above the full-analysis ceiling there is no whole-board scan — just the
/// seeds' constraint component, walked outward from the click. Verdicts come
/// ONLY from the relaxed rule: a sealed+rigid pocket is forced regardless of
/// the rest of the board, and rigidity makes its odds exact without global
/// knowledge. Everything else returns nil, honestly — "no safe cell anywhere"
/// and open-field odds are global questions, and the forced guesses a
/// million-cell board realistically has ARE sealed pockets.
extension GuessOdds {
    static func hugeVerdict(_ game: Game, seeds: [Coord], chordOpened: Bool) -> Verdict? {
        guard let pos = localPosition(for: game, around: seeds) else { return nil }
        let seedIndices = seeds.compactMap { pos.unknownIndex[$0] }
        guard seedIndices.count == seeds.count else { return nil }

        let census = Census(pos)
        guard !seedIndices.contains(where: { census.certainMine.contains($0) }) else {
            return nil  // suicide, not a gamble (matches the full path's not-forced)
        }
        let uncertain = seedIndices.filter { !census.certainSafe.contains($0) }
        guard !uncertain.isEmpty,
            uncertain.allSatisfy({ census.membership[$0] != nil }),
            let (pocket, tally) = unresolvablePocket(
                seeds: uncertain, census: census, pos: pos, game: game)
        else { return nil }

        let total = tally.solutions.values.reduce(0, +)
        guard total > 0 else { return nil }
        let survival: Double
        if chordOpened {
            // P(every opened cell safe): re-enumerate with them pinned safe.
            // (Certain-safe opened cells contribute a factor of 1 — pinning the
            // uncertain ones is equivalent.)
            var local: [Int: Int] = [:]
            for (i, cell) in pocket.cells.enumerated() { local[cell] = i }
            let forcedSafe = Set(uncertain.compactMap { local[$0] })
            guard let safeTally = enumerate(component: pocket, forcedSafe: forcedSafe)
            else { return nil }
            survival = safeTally.solutions.values.reduce(0, +) / total
        } else {
            guard let local = pocket.cells.firstIndex(of: seedIndices[0]) else { return nil }
            survival = 1 - tally.mineSolutions[local].values.reduce(0, +) / total
        }
        return Verdict(forced: true, survival: max(0, min(1, survival)))
    }

    /// Build just the seeds' constraint component by walking outward: unknowns →
    /// their revealed neighbours' constraints → those constraints' unknowns → …
    /// Bails (nil) past the component cap, so an easy-density board's sprawling
    /// frontier costs a bounded walk, never a scan.
    private static func localPosition(for game: Game, around seeds: [Coord]) -> Position? {
        let board = game.board
        var unknownIndex: [Coord: Int] = [:]
        var unknownCoords: [Coord] = []
        var queue: [Coord] = []
        func register(_ c: Coord) -> Bool {
            guard unknownIndex[c] == nil else { return true }
            guard unknownCoords.count < maxComponentCells else { return false }
            unknownIndex[c] = unknownCoords.count
            unknownCoords.append(c)
            queue.append(c)
            return true
        }
        for s in seeds where board[s].state != .revealed {
            guard register(s) else { return nil }
        }
        var constraints: [(cells: [Int], count: Int)] = []
        var seen = Set<Coord>()
        while let unknown = queue.popLast() {
            for r in board.topology.neighbors(of: unknown)
            where board[r].state == .revealed && seen.insert(r).inserted {
                var cells: [Int] = []
                for n in board.topology.neighbors(of: r) where board[n].state != .revealed {
                    guard register(n) else { return nil }
                    cells.append(unknownIndex[n]!)
                }
                constraints.append((cells: cells, count: board[r].adjacentMines))
            }
        }
        let comps = components(unknownCount: unknownCoords.count, constraints: constraints)
        var tallies: [ComponentTally] = []
        for component in comps {
            guard component.cells.count <= maxComponentCells,
                let tally = enumerate(component: component), !tally.solutions.isEmpty
            else { return nil }
            tallies.append(tally)
        }
        // interiorCount 0: the local path never takes the interior branch (seeds
        // without a constraint never reach a pocket), and no verdict() runs here.
        return Position(
            unknownIndex: unknownIndex, unknownCoords: unknownCoords, tallies: tallies,
            components: comps, interiorCount: 0, mines: game.mineCount)
    }
}
