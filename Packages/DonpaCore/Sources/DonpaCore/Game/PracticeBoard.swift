import Foundation

/// Fully deduction-solvable ("no-guess") mine layouts for The Range — by REPAIR,
/// not resampling: place mines, run the solver, and whenever it gets stuck,
/// relocate the mines hiding in the stuck frontier (the hidden cells the numbers
/// can see) out of sight, then RESUME solving from exactly the numbers those
/// moves changed. Local fixes converge where rerolling can't (the chance a board
/// is spontaneously guess-free decays exponentially with area), and resuming
/// instead of re-solving keeps the total work linear. Two rarer stalls are also
/// handled: flag-sealed regions get a doorway opened through their wall, and a
/// drained interior falls back to frontier refuges (with the extra reseeding
/// that implies). Measured at The Range's 12% across its XS–XL ladder: zero
/// failures in 960 boards, worst case ~1 s (XL); the huge boards stay out of the
/// mode by design — their endgames defeat repair-by-relocation.
public enum PracticeBoard {
    /// Repair rounds per seed (a round is cheap: O(stuck front) plus a resume,
    /// never a board scan or re-solve), and fresh reseeds before giving up: at
    /// The Range's sizes a fresh seed succeeds most of the time in ≤ ~80 ms, so
    /// a deep reseed budget drives failure to effectively zero.
    static let maxRounds = 400
    static let maxSeeds = 10
    /// Fresh-solve verifications per seed (each failure re-enters repair).
    static let maxVerifyRounds = 12

    /// A solvable layout, first-click-safe around `firstClick`, or nil if the
    /// budget runs out (the caller may fall back to a plain layout).
    public static func mines<R: RandomNumberGenerator>(
        topology: any RectangularTopology, mineCount: Int, firstClick: Coord,
        using rng: inout R
    ) -> Set<Coord>? {
        guard let click = topology.normalize(firstClick) else { return nil }
        // The first-click flood guarantee: the click's neighbourhood stays clear,
        // in placement AND in every relocation.
        var safeZone: Set<Coord> = [click]
        safeZone.formUnion(topology.neighbors(of: click))
        let solver = Solver()

        for _ in 0..<maxSeeds {
            var candidate = MinePlacer.placeMines(
                topology: topology, mineCount: mineCount, firstClick: click, using: &rng)
            // Repair finds a layout whose REPAIR TRAJECTORY solves — but that
            // trajectory may lean on flag knowledge earned under earlier
            // layouts, which a fresh solve can't re-derive. So the guarantee
            // comes from verification: only a layout that just solved FROM
            // SCRATCH is returned, and a failed verification feeds its stuck
            // front straight back into repair.
            for _ in 0..<maxVerifyRounds {
                var game = Game(topology: topology, mines: candidate)
                var (result, reported) = solver.solveTracked(
                    &game, firstClick: click, using: &rng)
                if result.solvedWithoutGuessing { return candidate }

                // The stuck FRONT, carried across rounds: a resume only reports
                // numbers it re-examined, so earlier stuck numbers stay in the
                // front until their hidden neighbourhood actually resolves.
                var front = Set(reported)
                var round = 0
                while !result.solvedWithoutGuessing, result.status == .playing,
                    round < maxRounds
                {
                    round += 1
                    let stuck = liveStuck(front: &front, in: game)
                    guard
                        let seeds = stuck.isEmpty
                            ? openDoorway(in: &game, safeZone: safeZone, using: &rng)
                            : relocate(stuck: stuck, in: &game, safeZone: safeZone, using: &rng)
                    else { break }
                    (result, reported) = solver.continueTracked(&game, from: seeds, using: &rng)
                    front.formUnion(reported)
                }
                guard result.solvedWithoutGuessing else { break }  // repair failed → reseed
                candidate = game.board.mineCoords
            }
        }
        return nil
    }

    /// Prune the front's resolved numbers; collect the hidden mines the live
    /// front can see — those are what block deduction.
    private static func liveStuck(front: inout Set<Coord>, in game: Game) -> [Coord] {
        let topology = game.board.topology
        var stuck: [Coord] = []
        var stuckSeen = Set<Coord>()
        var liveFront = Set<Coord>()
        for n in front {
            var sawHidden = false
            for h in topology.neighbors(of: n) where game.board[h].state == .hidden {
                sawHidden = true
                if game.board[h].isMine, stuckSeen.insert(h).inserted {
                    stuck.append(h)
                }
            }
            if sawHidden { liveFront.insert(n) }
        }
        front = liveFront
        return stuck
    }

    /// Move the stuck mines to refuges; the seeds to resume from are the numbers
    /// beside each VACATED cell — and beside the refuge too, when the endgame
    /// forced a frontier refuge.
    private static func relocate<R: RandomNumberGenerator>(
        stuck: [Coord], in game: inout Game, safeZone: Set<Coord>, using rng: inout R
    ) -> [Coord]? {
        guard
            let refuges = refuges(count: stuck.count, in: game, safeZone: safeZone, using: &rng)
        else { return nil }
        let topology = game.board.topology
        var seeds: [Coord] = []
        for (mine, refuge) in zip(stuck, refuges) {
            game.moveMineForGeneration(from: mine, to: refuge)
            for n in topology.neighbors(of: mine)
            where game.board[n].state == .revealed {
                seeds.append(n)
            }
            for n in topology.neighbors(of: refuge)
            where game.board[n].state == .revealed {
                seeds.append(n)
            }
        }
        return seeds
    }

    /// No number sees any hidden mine, yet the board isn't won: the solver's own
    /// flag walls have SEALED the remaining hidden regions (nothing can ever
    /// deduce into them). Open a doorway: take a wall flag that touches the
    /// outside numbers, banish its mine deep into a sealed region, and unflag
    /// it — the outside numbers drop by one, reveal the door cell, and deduction
    /// flows into the pocket.
    private static func openDoorway<R: RandomNumberGenerator>(
        in game: inout Game, safeZone: Set<Coord>, using rng: inout R
    ) -> [Coord]? {
        guard let door = doorway(in: game),
            let refuge = refuges(count: 1, in: game, safeZone: safeZone, using: &rng)?.first
        else { return nil }
        game.moveMineForGeneration(from: door, to: refuge)
        game.toggleFlag(door)
        return game.board.topology.neighbors(of: door).filter {
            game.board[$0].state == .revealed
        }
    }

    /// A flag on a sealed region's wall, touching both the revealed outside and
    /// the hidden inside — the cell to turn into the region's doorway. Every
    /// wall flag has a revealed neighbour (rule 1 flagged it from one), so when
    /// sealed regions exist a door always does too.
    private static func doorway(in game: Game) -> Coord? {
        let topology = game.board.topology
        for c in game.board.flaggedCoords {
            let neighbours = topology.neighbors(of: c)
            if neighbours.contains(where: { game.board[$0].state == .revealed }),
                neighbours.contains(where: { game.board[$0].state == .hidden })
            {
                return c
            }
        }
        return nil
    }

    /// `count` distinct interior refuge cells — hidden, mine-free, outside the
    /// safe zone, with NO revealed neighbour (so a move changes no visible
    /// number). Rejection-sampled first (the interior dominates most of a
    /// repair run); when the endgame has drained it too dry for sampling, a
    /// full scan finds whatever genuinely remains. nil only when the interior
    /// truly can't host the stuck mines.
    private static func refuges<R: RandomNumberGenerator>(
        count: Int, in game: Game, safeZone: Set<Coord>, using rng: inout R
    ) -> [Coord]? {
        let topology = game.board.topology
        func qualifies(_ c: Coord, chosen: Set<Coord>) -> Bool {
            game.board[c].state == .hidden && !game.board[c].isMine
                && !safeZone.contains(c) && !chosen.contains(c)
                && !topology.neighbors(of: c).contains {
                    game.board[$0].state == .revealed
                }
        }

        let cells = topology.cellCount
        var out: [Coord] = []
        var chosen = Set<Coord>()
        var attempts = 0
        let budget = max(200, count * 40)
        while out.count < count && attempts < budget {
            attempts += 1
            let c = topology.coord(at: Int.random(in: 0..<cells, using: &rng))
            guard qualifies(c, chosen: chosen) else { continue }
            chosen.insert(c)
            out.append(c)
        }
        if out.count == count { return out }

        // Sampling starved (thin endgame interior) — scan for the rest.
        var remainder: [Coord] = []
        for c in game.board.allCoords where qualifies(c, chosen: chosen) {
            remainder.append(c)
        }
        remainder.shuffle(using: &rng)
        out.append(contentsOf: remainder.prefix(count - out.count))
        if out.count == count { return out }

        // The interior is truly gone (endgame): fall back to ANY hidden,
        // mine-free cell — such a refuge sits beside numbers, which is fine as
        // long as the caller re-seeds the refuge's neighbours too (it does).
        var anywhere: [Coord] = []
        for c in game.board.allCoords
        where game.board[c].state == .hidden && !game.board[c].isMine
            && !safeZone.contains(c) && !chosen.contains(c)
        {
            anywhere.append(c)
        }
        guard out.count + anywhere.count >= count else { return nil }
        anywhere.shuffle(using: &rng)
        out.append(contentsOf: anywhere.prefix(count - out.count))
        return out
    }
}
