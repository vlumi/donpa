import Foundation

/// One logged win for the pace window: when, how long, and the board's 3BV.
/// The rolling per-config log of these is the raw material for pace displays
/// and the (later) skill rank — collected at the finest grain so every
/// grouping decision stays reversible.
public struct RecentWin: Equatable, Hashable, Sendable, Codable {
    public let date: Date
    public let centiseconds: Int
    /// The board's minimum number of taps (see `Pace.threeBV`).
    public let threeBV: Int

    public init(date: Date, centiseconds: Int, threeBV: Int) {
        self.date = date
        self.centiseconds = centiseconds
        self.threeBV = threeBV
    }

    /// Pace in 3BV per second — the luck-normalized sweep rate: a lucky
    /// low-3BV board gives a fast TIME but a normal PACE. A clock that
    /// truncated to 0 (a single-tap instant clear) clamps to one centisecond —
    /// "faster than measurable", never a zero that would read as the slowest.
    public var pace: Double {
        Double(threeBV) * 100 / Double(max(centiseconds, 1))
    }
}

public enum Pace {
    /// 3BV: a board's minimum number of taps — one per OPENING (a connected
    /// region of zero-adjacency cells opens, with its numbered border, from a
    /// single tap) plus one per safe numbered cell not adjacent to any zero.
    /// Uses the board's own adjacency, so it's equally defined on square,
    /// hex, and wrapped boards. One linear pass; a dense visited buffer keeps
    /// even a million-cell board cheap.
    public static func threeBV(of board: Board) -> Int {
        let topology = board.topology
        var visited = [Bool](repeating: false, count: topology.width * topology.height)
        func idx(_ c: Coord) -> Int? { topology.index(of: c) }

        var taps = 0
        for c in topology.allCoords() {
            guard let i = idx(c), !visited[i] else { continue }
            let cell = board[c]
            guard !cell.isMine, cell.adjacentMines == 0 else { continue }
            // One tap opens this whole zero region; its numbered border
            // comes along for free.
            taps += 1
            visited[i] = true
            var stack = [c]
            while let cur = stack.popLast() {
                for n in topology.neighbors(of: cur) where !board[n].isMine {
                    guard let ni = idx(n), !visited[ni] else { continue }
                    visited[ni] = true
                    if board[n].adjacentMines == 0 { stack.append(n) }
                }
            }
        }
        for c in topology.allCoords() {
            guard let i = idx(c), !visited[i] else { continue }
            let cell = board[c]
            guard !cell.isMine, cell.adjacentMines > 0 else { continue }
            taps += 1
        }
        return taps
    }

    /// The median pace over a window of wins, each entry WEIGHTED BY ITS 3BV —
    /// a big board is more evidence than an XS one, so quantization noise
    /// washes out instead of being excluded. Nil for an empty window.
    public static func medianPace(of wins: [RecentWin]) -> Double? {
        guard !wins.isEmpty else { return nil }
        let sorted = wins.sorted { $0.pace < $1.pace }
        let totalWeight = sorted.reduce(0) { $0 + $1.threeBV }
        guard totalWeight > 0 else { return nil }
        var running = 0
        for win in sorted {
            running += win.threeBV
            if running * 2 >= totalWeight { return win.pace }
        }
        return sorted.last?.pace
    }
}
