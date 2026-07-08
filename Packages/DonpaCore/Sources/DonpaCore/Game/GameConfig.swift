/// A fully-specified, playable board configuration — the single source of
/// dimensions, mine count, topology, display label, and the stable persistence
/// key used by the scoreboard.
///
/// Three **board families** — the one vocabulary the New Game pages, storage
/// keys, scoreboard filters, and gating all speak:
/// - **Basic**: the three original presets (Beginner / Intermediate / Expert).
/// - **Grid**: square cells (8 neighbours), `Size × Density`, Flat or Round edges.
/// - **Hive**: hex cells (6 neighbours), same axes, denser per tier (see `Density`).
///
/// **Edges** are Flat (a map you can fall off) or Round (the world curves back —
/// a torus that scrolls forever). Every axis is encoded explicitly in the storage
/// key, which also carries concrete geometry (`WxH|mN`) — so re-tuning a tier
/// produces a new key (new scoreboard entry) rather than re-pointing old scores.

import Foundation

/// Board width/height/mine-count, computed from a `GameConfig`.
public struct BoardDimensions: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let mines: Int
}

/// The top-level board family — one page each in the New Game picker, and the
/// first axis of every storage key.
public enum BoardFamily: String, CaseIterable, Sendable, Codable, Identifiable {
    case basic, grid, hive
    /// Drills (FI Soha, JA 演習): guaranteed no-guess practice
    /// boards at 12%, XS–XL — see `PracticeBoard`.
    case practice

    /// Explicit order = every family-enumerating surface's order (New Game
    /// pager, scoreboard filters, head-to-head, breakdowns): Drills sits
    /// leftmost as the warm-up before the real families.
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

    /// Board dimensions and mine count, shown under the picker carousel.
    public var detail: String {
        let d = dimensions
        return String(
            localized: "\(d.width)×\(d.height) · \(d.mines) mines", bundle: .module,
            comment: "Basic preset detail: WIDTH×HEIGHT · N mines")
    }

    /// A short, playful tagline shown under the picker carousel.
    public var tagline: String {
        switch self {
        case .beginner: return String(localized: "Boots on, recruit", bundle: .module)
        case .intermediate: return String(localized: "Things get spicy", bundle: .module)
        case .expert: return String(localized: "One wrong step…", bundle: .module)
        }
    }
}

/// Grid/Hive board sizes, shirt-sized XS…XXXL. Side lengths are powers of two
/// (8…256, then 1024), so every board is even-sided — the property a hex torus
/// needs for consistent wrap-around (odd height breaks hex adjacency symmetry). The
/// top rung jumps ×4 to 1024² (~1M cells): the effectively-unwinnable stress case
/// for viewport culling. XS–XXL are the playable tiers.
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

    /// Board dimensions, shown under the picker carousel.
    public var detail: String {
        String(
            localized: "\(side)×\(side)", bundle: .module,
            comment: "Board size detail: SIDE×SIDE")
    }

    /// A short, playful tagline shown under the picker carousel.
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

/// Grid/Hive difficulty = mine density (fraction of cells). Even 2-point steps,
/// from fair (easy) to near-unsolvable-by-logic (insane), chosen via solver
/// analysis on the power-of-two size ladder: bigger boards saturate to ~100%
/// forced-guess sooner, so the (original) top tier stays modest to keep the
/// tiers distinct on the boards people actually play. **Lunatic (20%, classic
/// Expert's density) sits deliberately past that line**: essentially every game
/// demands forced gambles (XS 90% / S 98% solver guess-rate vs Legend's
/// 81%/91%) — the tier where the luck tracking is the game's texture.
///
/// **Hive runs +2 points denser than Grid** (12/14/16/18/20% vs 10/12/14/16/18%):
/// a hex cell has 6 neighbours vs 8, so the same mine% cascades more and plays
/// noticeably easier (the small/sparse boards were near one-tap). The bump matches
/// hex difficulty back to square roughly tier-for-tier. See the TierAnalysis dev
/// tool, which measures both topologies.
public enum Density: String, CaseIterable, Sendable, Codable {
    case easy, normal, hard, brutal, insane, lunatic

    /// Mine fraction for a given family. Grid is the base ladder; Hive adds two
    /// points per tier to offset its gentler 6-neighbour cascades.
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

    /// Sapper-themed skill tiers (ascending). Display-only — the `rawValue`
    /// (easy/normal/…) is unchanged, so scoreboard keys are unaffected.
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

    /// Mine density as a whole percent for the family being picked, shown under
    /// the picker carousel — a Hive tier honestly shows its denser number.
    public func detail(hex: Bool) -> String {
        String(
            localized: "\(Int((fraction(hex: hex) * 100).rounded()))% mines", bundle: .module,
            comment: "Difficulty detail: N% mines")
    }

    /// A short, playful tagline shown under the picker carousel.
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

    /// Ascending rank insignia, shown language-free in the compact difficulty
    /// picker; `label` stays the accessibility name.
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

/// The board's edge behaviour. **Flat** is a map with edges you can fall off;
/// **Round** is a world that curves back on itself (a torus — pan off one side
/// and the other flows in). Basic boards are always Flat.
public enum BoardEdges: String, Sendable, Codable, CaseIterable, Identifiable {
    case flat
    /// Edges wrap (torus) — `Wrapped{Square,Hex}Topology`. Grid/Hive only.
    case round

    public var id: String { rawValue }

    /// Whether the board wraps into a torus — the mechanic behind the name.
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
    /// Drills: a square no-guess board (see `PracticeBoard`) — size is the
    /// only axis; density is fixed at `PracticeBoard.mineFraction`, edges Flat.
    case practice(BoardSize)

    /// The board family — the page this config lives on.
    public var family: BoardFamily {
        switch self {
        case .basic: return .basic
        case .grid: return .grid
        case .hive: return .hive
        case .practice: return .practice
        }
    }

    /// Flat for Basic and Drills; the chosen edges for Grid/Hive.
    public var edges: BoardEdges {
        switch self {
        case .basic, .practice: return .flat
        case .grid(_, _, let edges), .hive(_, _, let edges): return edges
        }
    }

    /// Hexagonal cells (the Hive family)?
    public var isHex: Bool { family == .hive }

    /// The board size, or nil for a Basic config.
    public var size: BoardSize? {
        switch self {
        case .basic: return nil
        case .grid(let size, _, _), .hive(let size, _, _): return size
        case .practice(let size): return size
        }
    }

    /// The Grid/Hive difficulty tier, or nil for Basic and Drills.
    public var density: Density? {
        switch self {
        case .basic, .practice: return nil
        case .grid(_, let density, _), .hive(_, let density, _): return density
        }
    }

    /// Drills' size ladder: XS–XL. The huge boards stay out — their
    /// endgames defeat the no-guess generator, and the mode's audience doesn't
    /// need a million cells to learn or speedrun on.
    public static let practiceSizes: [BoardSize] = [.xs, .s, .m, .l, .xl]

    /// Build a Grid/Hive config from its axes; nil for `.basic` (presets carry no
    /// axes — construct those with `.basic(preset)` directly).
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

    /// The board geometry to play on, the full family × edges matrix (all
    /// `RectangularTopology`, which `Board` requires for flat storage). Every
    /// Grid/Hive size is even-sided (powers of two), so the wrapped-hex torus is
    /// always valid.
    public var topology: any RectangularTopology {
        switch (isHex, edges.wraps) {
        case (false, false): return BoundedSquareTopology(width: width, height: height)
        case (false, true): return WrappedSquareTopology(width: width, height: height)
        case (true, false): return HexTopology(width: width, height: height)
        case (true, true): return WrappedHexTopology(width: width, height: height)
        }
    }

    /// The pixel layout matching the family — the `CellLayout` the renderer
    /// positions and hit-tests with. Pairs with `topology`; changes when a new game
    /// switches family, so the scene reads it from the live config rather than
    /// caching it.
    public func layout(cellSize: CGFloat = 32) -> any CellLayout {
        isHex ? HexLayout(cellSize: cellSize) : SquareLayout(cellSize: cellSize)
    }

    /// Human-facing label; Grid/Hive configs read as "Size · Density".
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

    /// Context-free label naming every distinguishing axis, for lists that mix
    /// families and edges in one flat table (head-to-head) where `label` alone
    /// is ambiguous. Flat is the unmarked default; Round is called out.
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

    /// Stable, versioned, geometry-bearing persistence key. Encodes every axis
    /// explicitly so keys never become ambiguous. `v2` = the family vocabulary
    /// (v1 spoke classic/modern + a shape axis; v1 keys are orphaned by the 0.3.0
    /// score reset, not migrated).
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

    /// The configs a family offers, in display order. Basic ignores `edges` (its
    /// presets are always Flat); Grid/Hive enumerate size × density at the given
    /// edges — the scoreboard's Family + Edges filters narrow to exactly one such
    /// list.
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

    // Convenience shortcuts for the basic presets.
    public static let beginner = GameConfig.basic(.beginner)
    public static let intermediate = GameConfig.basic(.intermediate)
    public static let expert = GameConfig.basic(.expert)
}
