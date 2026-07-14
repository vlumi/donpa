import Foundation

/// One logged win for the pace window — collected at the finest grain so every
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

    /// 3BV per second — the luck-normalized sweep rate: a lucky low-3BV board
    /// gives a fast TIME but a normal PACE. A clock truncated to 0 clamps to one
    /// centisecond ("faster than measurable"), never a zero that reads slowest.
    public var pace: Double {
        Double(threeBV) * 100 / Double(max(centiseconds, 1))
    }
}

public enum Pace {
    /// 3BV: a board's minimum number of taps — one per OPENING (a connected zero
    /// region plus its numbered border) plus one per safe numbered cell not
    /// adjacent to any zero. Uses the board's own adjacency, so it's equally
    /// defined on square, hex, and wrapped boards.
    public static func threeBV(of board: Board) -> Int {
        let topology = board.topology
        var visited = [Bool](repeating: false, count: topology.width * topology.height)
        func idx(_ c: Coord) -> Int? { topology.index(of: c) }

        var taps = 0
        for c in topology.allCoords() {
            guard let i = idx(c), !visited[i] else { continue }
            let cell = board[c]
            guard !cell.isMine, cell.adjacentMines == 0 else { continue }
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

    /// Median pace, each win WEIGHTED BY ITS 3BV — a big board is more evidence
    /// than an XS one. Nil for an empty window.
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
