/// A fully-specified, playable board configuration — the single source of
/// dimensions, mine count, topology, display label, and the stable persistence
/// key used by the scoreboard.

import Foundation

public struct BoardDimensions: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let mines: Int
}

public enum BoardFamily: String, CaseIterable, Sendable, Codable, Identifiable {
    case basic, grid, hive
    /// Drills: guaranteed no-guess practice boards — see `PracticeBoard`.
    case practice

    /// Explicit order — the display order of every family-enumerating surface;
    /// Drills sits leftmost as the warm-up.
    public static var allCases: [BoardFamily] { [.practice, .basic, .grid, .hive] }

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .basic: return String(localized: "Basic", bundle: .module)
        case .grid: return String(localized: "Grid", bundle: .module)
        case .hive: return String(localized: "Hive", bundle: .module)
        case .practice: return String(localized: "Drills", bundle: .module)
        }
    }
}

public enum BasicPreset: String, CaseIterable, Sendable, Codable {
    case beginner, intermediate, expert

    var dimensions: BoardDimensions {
        switch self {
        case .beginner: return BoardDimensions(width: 9, height: 9, mines: 10)
        case .intermediate: return BoardDimensions(width: 16, height: 16, mines: 40)
        case .expert: return BoardDimensions(width: 30, height: 16, mines: 99)
        }
    }

    public var label: String {
        switch self {
        case .beginner: return String(localized: "Beginner", bundle: .module)
        case .intermediate: return String(localized: "Intermediate", bundle: .module)
        case .expert: return String(localized: "Expert", bundle: .module)
        }
    }

    public var detail: String {
        let d = dimensions
        return String(
            localized: "\(d.width)×\(d.height) · \(d.mines) mines", bundle: .module,
            comment: "Basic preset detail: WIDTH×HEIGHT · N mines")
    }

    public var tagline: String {
        switch self {
        case .beginner: return String(localized: "Boots on, recruit", bundle: .module)
        case .intermediate: return String(localized: "Things get spicy", bundle: .module)
        case .expert: return String(localized: "One wrong step…", bundle: .module)
        }
    }
}

/// Grid/Hive board sizes. Side lengths are powers of two, so every board is
/// even-sided — required for consistent hex wrap-around. XS–XXL are the
/// playable tiers; XXXL (1024², ~1M cells) is the viewport-culling stress case.
public enum BoardSize: String, CaseIterable, Sendable, Codable {
    case xs, s, m, l, xl, xxl, xxxl

    var side: Int {
        switch self {
        case .xs: return 8
        case .s: return 16
        case .m: return 32
        case .l: return 64
        case .xl: return 128
        case .xxl: return 256
        case .xxxl: return 1024
        }
    }

    public var label: String {
        switch self {
        case .xs: return String(localized: "XS", bundle: .module)
        case .s: return String(localized: "S", bundle: .module)
        case .m: return String(localized: "M", bundle: .module)
        case .l: return String(localized: "L", bundle: .module)
        case .xl: return String(localized: "XL", bundle: .module)
        case .xxl: return String(localized: "XXL", bundle: .module)
        case .xxxl: return String(localized: "XXXL", bundle: .module)
        }
    }

    public var detail: String {
        String(
            localized: "\(side)×\(side)", bundle: .module,
            comment: "Board size detail: SIDE×SIDE")
    }

    public var tagline: String {
        switch self {
        case .xs: return String(localized: "Over before your coffee", bundle: .module)
        case .s: return String(localized: "A quick recon", bundle: .module)
        case .m: return String(localized: "A proper mission", bundle: .module)
        case .l: return String(localized: "Clear your evening", bundle: .module)
        case .xl: return String(localized: "Pack a lunch", bundle: .module)
        case .xxl: return String(localized: "Pack a lunch. And dinner.", bundle: .module)
        case .xxxl: return String(localized: "Abandon all hope, ye who enter", bundle: .module)
        }
    }
}

/// Grid/Hive difficulty = mine density (fraction of cells), tuned via solver
/// analysis (see the TierAnalysis dev tool). Lunatic (20%) deliberately sits
/// past the point where essentially every game demands forced gambles. Hive
/// runs +2 points denser than Grid: hex cells have 6 neighbours instead of 8,
/// so the same fraction cascades more and plays noticeably easier.
public enum Density: String, CaseIterable, Sendable, Codable {
    case easy, normal, hard, brutal, insane, lunatic

    func fraction(hex: Bool) -> Double {
        base + (hex ? 0.02 : 0)
    }

    private var base: Double {
        switch self {
        case .easy: return 0.10
        case .normal: return 0.12
        case .hard: return 0.14
        case .brutal: return 0.16
        case .insane: return 0.18
        case .lunatic: return 0.20
        }
    }

    /// Display-only — scoreboard keys use the unchanged `rawValue`.
    public var label: String {
        switch self {
        case .easy: return String(localized: "Trainee", bundle: .module)
        case .normal: return String(localized: "Sapper", bundle: .module)
        case .hard: return String(localized: "Veteran", bundle: .module)
        case .brutal: return String(localized: "Ace", bundle: .module)
        case .insane: return String(localized: "Legend", bundle: .module)
        case .lunatic: return String(localized: "Lunatic", bundle: .module)
        }
    }

    public func detail(hex: Bool) -> String {
        String(
            localized: "\(Int((fraction(hex: hex) * 100).rounded()))% mines", bundle: .module,
            comment: "Difficulty detail: N% mines")
    }

    public var tagline: String {
        switch self {
        case .easy: return String(localized: "Easy does it", bundle: .module)
        case .normal: return String(localized: "Mind your step", bundle: .module)
        case .hard: return String(localized: "Sweating now", bundle: .module)
        case .brutal: return String(localized: "This is mean", bundle: .module)
        case .insane: return String(localized: "No pain, no gain", bundle: .module)
        case .lunatic: return String(localized: "The board fights back", bundle: .module)
        }
    }

    /// Language-free rank marks; `label` stays the accessibility name.
    public enum Insignia: Sendable {
        case chevrons(Int)  // N stacked stripes
        case star  // single officer star
        case staredLaurel  // star in a laurel wreath (the mortal apex)
        case moonedLaurel  // crescent moon in the laurel — luna, for the Lunatic
    }
    public var insignia: Insignia {
        switch self {
        case .easy: return .chevrons(1)
        case .normal: return .chevrons(2)
        case .hard: return .chevrons(3)
        case .brutal: return .star
        case .insane: return .staredLaurel
        case .lunatic: return .moonedLaurel
        }
    }
}

/// **Flat**: bounded edges. **Round**: the board wraps into a torus. Basic
/// boards are always Flat.
public enum BoardEdges: String, Sendable, Codable, CaseIterable, Identifiable {
    case flat
    case round

    public var id: String { rawValue }

    public var wraps: Bool { self == .round }

    public var label: String {
        switch self {
        case .flat: return String(localized: "Flat", bundle: .module)
        case .round: return String(localized: "Round", bundle: .module)
        }
    }
}

public enum GameConfig: Hashable, Sendable {
    case basic(BasicPreset)
    case grid(BoardSize, Density, BoardEdges)
    case hive(BoardSize, Density, BoardEdges)
    /// Drills: density fixed at `PracticeBoard.mineFraction`, edges always Flat.
    case practice(BoardSize)

    public var family: BoardFamily {
        switch self {
        case .basic: return .basic
        case .grid: return .grid
        case .hive: return .hive
        case .practice: return .practice
        }
    }

    public var edges: BoardEdges {
        switch self {
        case .basic, .practice: return .flat
        case .grid(_, _, let edges), .hive(_, _, let edges): return edges
        }
    }

    public var isHex: Bool { family == .hive }

    public var size: BoardSize? {
        switch self {
        case .basic: return nil
        case .grid(let size, _, _), .hive(let size, _, _): return size
        case .practice(let size): return size
        }
    }

    public var density: Density? {
        switch self {
        case .basic, .practice: return nil
        case .grid(_, let density, _), .hive(_, let density, _): return density
        }
    }

    /// XS–XL only: the huge boards' endgames defeat the no-guess generator.
    public static let practiceSizes: [BoardSize] = [.xs, .s, .m, .l, .xl]

    /// nil for families that don't carry the size/density/edges axes.
    public static func custom(
        _ family: BoardFamily, _ size: BoardSize, _ density: Density, _ edges: BoardEdges
    ) -> GameConfig? {
        switch family {
        case .basic, .practice: return nil
        case .grid: return .grid(size, density, edges)
        case .hive: return .hive(size, density, edges)
        }
    }

    public var width: Int { dims.width }
    public var height: Int { dims.height }
    public var mineCount: Int { dims.mines }

    private var dims: BoardDimensions {
        switch self {
        case .basic(let preset):
            return preset.dimensions
        case .grid(let size, let density, _), .hive(let size, let density, _):
            let side = size.side
            let mines = Int((Double(side * side) * density.fraction(hex: isHex)).rounded())
            return BoardDimensions(width: side, height: side, mines: mines)
        case .practice(let size):
            let side = size.side
            let mines = Int((Double(side * side) * PracticeBoard.mineFraction).rounded())
            return BoardDimensions(width: side, height: side, mines: mines)
        }
    }

    /// All cases are `RectangularTopology` (`Board` requires flat storage).
    /// Grid/Hive sides are even, so the wrapped-hex torus is always valid.
    public var topology: any RectangularTopology {
        switch (isHex, edges.wraps) {
        case (false, false): return BoundedSquareTopology(width: width, height: height)
        case (false, true): return WrappedSquareTopology(width: width, height: height)
        case (true, false): return HexTopology(width: width, height: height)
        case (true, true): return WrappedHexTopology(width: width, height: height)
        }
    }

    /// Pairs with `topology`; family-dependent, so callers must not cache it
    /// across games.
    public func layout(cellSize: CGFloat = 32) -> any CellLayout {
        isHex ? HexLayout(cellSize: cellSize) : SquareLayout(cellSize: cellSize)
    }

    public var label: String {
        switch self {
        case .basic(let preset):
            return preset.label
        case .grid(let size, let density, _), .hive(let size, let density, _):
            return "\(size.label) · \(density.label)"
        case .practice(let size):
            return size.label
        }
    }

    /// Names every distinguishing axis, for flat lists that mix families and
    /// edges where `label` alone is ambiguous. Flat is the unmarked default.
    public var fullLabel: String {
        switch self {
        case .basic(let preset):
            return preset.label
        case .grid(let size, let density, let edges), .hive(let size, let density, let edges):
            let base = "\(family.label) · \(size.label) · \(density.label)"
            return edges.wraps ? "\(base) · \(edges.label)" : base
        case .practice(let size):
            return "\(family.label) · \(size.label)"
        }
    }

    /// Stable, versioned persistence key, encoding every axis plus concrete
    /// geometry — re-tuning a tier mints a new key (new scoreboard entry)
    /// rather than re-pointing old scores.
    ///
    ///   basic:    v2|basic|beginner
    ///   grid:     v2|grid|flat|16x16|m31
    ///   hive:     v2|hive|round|16x16|m36
    ///   practice: v2|practice|16x16|m31
    public var storageKey: String {
        switch self {
        case .basic(let preset):
            return "v2|basic|\(preset.rawValue)"
        case .grid, .hive:
            return
                "v2|\(family.rawValue)|\(edges.rawValue)|\(width)x\(height)|m\(mineCount)"
        case .practice:
            return "v2|practice|\(width)x\(height)|m\(mineCount)"
        }
    }

    /// A family's configs in display order; Basic ignores `edges`.
    public static func configs(family: BoardFamily, edges: BoardEdges = .flat) -> [GameConfig] {
        switch family {
        case .basic:
            return BasicPreset.allCases.map(GameConfig.basic)
        case .grid, .hive:
            return BoardSize.allCases.flatMap { size in
                Density.allCases.compactMap { custom(family, size, $0, edges) }
            }
        case .practice:
            return practiceSizes.map(GameConfig.practice)
        }
    }

    public static let beginner = GameConfig.basic(.beginner)
    public static let intermediate = GameConfig.basic(.intermediate)
    public static let expert = GameConfig.basic(.expert)
}
