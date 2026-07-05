import Foundation

/// Answers the New Game popup's "is there a game in progress?" questions from the set
/// of saved configs — driving the Start→Continue swap and the drill-down dots on the
/// selector chips.
///
/// The dots are TOP-DOWN by the popup's visual hierarchy (family → size → density →
/// edges): each level is filtered by the choices ABOVE it, so following the lit chips
/// down always lands on a real save (no dead ends). Pure — just set membership over
/// `GameConfig` axes — so it's headless-testable.
public struct InProgressIndex {
    /// The configs that currently have an in-progress save.
    private let configs: [GameConfig]

    public init(savedConfigs: [GameConfig]) {
        self.configs = savedConfigs
    }

    /// The exact current selection has a save → the button offers Continue.
    public func hasSave(for config: GameConfig) -> Bool {
        configs.contains(config)
    }

    // MARK: Drill-down dots (each level filtered by the ones above it)

    /// A family has a save (top of the hierarchy — no filter above it).
    public func familyHasSave(_ family: BoardFamily) -> Bool {
        configs.contains { $0.family == family }
    }

    /// A size has a save within the selected family (Grid/Hive only). Size is the first
    /// axis under family in the hierarchy.
    public func sizeHasSave(_ size: BoardSize, family: BoardFamily) -> Bool {
        configs.contains { $0.family == family && $0.size == size }
    }

    /// A density has a save within the selected family + size.
    public func densityHasSave(_ density: Density, family: BoardFamily, size: BoardSize) -> Bool {
        configs.contains { $0.family == family && $0.size == size && $0.density == density }
    }

    /// An edge has a save within the selected family + size + density.
    public func edgesHasSave(
        _ edges: BoardEdges, family: BoardFamily, size: BoardSize, density: Density
    ) -> Bool {
        configs.contains {
            $0.family == family && $0.size == size && $0.density == density && $0.edges == edges
        }
    }

    /// A Basic preset has a save (Basic has no size/density/edges axes to drill).
    public func presetHasSave(_ preset: BasicPreset) -> Bool {
        configs.contains { $0 == .basic(preset) }
    }
}
