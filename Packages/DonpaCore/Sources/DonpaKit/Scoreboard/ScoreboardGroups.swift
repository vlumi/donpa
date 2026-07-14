import DonpaCore
import SwiftUI

/// The score list's size grouping + full-clear standings, split from
/// `ScoreboardView` for the type-body-length budget (not `private`: Swift
/// `private` is file-scoped).
extension ScoreboardView {
    /// One header-plus-rows group of the filtered list: Grid/Hive get a labelled
    /// group per size; Basic and Drills are single unlabelled groups.
    struct ConfigGroup: Identifiable {
        let label: String?
        let configs: [GameConfig]
        var id: String { configs.first?.storageKey ?? "empty" }
    }

    static func groups(family: BoardFamily, edges: BoardEdges) -> [ConfigGroup] {
        switch family {
        case .basic:
            return [ConfigGroup(label: nil, configs: GameConfig.configs(family: .basic))]
        case .practice:
            // Drills has no density axis; a cross-size total is a deliberate
            // non-goal (practice, not a ladder).
            return [ConfigGroup(label: nil, configs: GameConfig.configs(family: .practice))]
        case .grid, .hive:
            return BoardSize.allCases.map { size in
                ConfigGroup(
                    label: size.label,
                    configs: Density.allCases.compactMap {
                        GameConfig.custom(family, size, $0, edges)
                    })
            }
        }
    }

    func standing(for group: ConfigGroup) -> FullClear.Standing {
        FullClear.standing(bests: group.configs.map { scoreboard.best(for: $0) })
    }

    @ViewBuilder func groupHeader(_ label: String, standing: FullClear.Standing) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: label)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            Spacer()
            standingLabel(standing)
        }
        .padding(.horizontal, Self.rowInset)
        .padding(.top, 12)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
    }

    /// Basic's trailing Total row — the classic trifecta's combined time.
    @ViewBuilder func trifectaFooter(standing: FullClear.Standing) -> some View {
        if standing.cleared > 0 {
            HStack(spacing: 8) {
                Text("Total", bundle: .module)
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                standingLabel(standing)
            }
            .padding(.horizontal, Self.rowInset)
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        }
    }

    /// "Full clear m:ss.t" once every config in the group is won; "n/N cleared"
    /// in progress; nothing when untouched — a row of "0/5" would drown the list.
    @ViewBuilder private func standingLabel(_ standing: FullClear.Standing) -> some View {
        if let sum = standing.sumCentiseconds {
            Text("Full clear \(TimeFormat.mmsst(centiseconds: sum))", bundle: .module)
                .font(.caption.monospacedDigit().bold())
                .numericCell()
        } else if standing.cleared > 0 {
            Text("\(standing.cleared)/\(standing.total) cleared", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
                .numericCell()
        }
    }
}
