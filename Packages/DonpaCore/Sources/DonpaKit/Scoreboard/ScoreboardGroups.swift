import DonpaCore
import SwiftUI

/// The score list's size grouping + full-clear standings: a slim subheader before
/// each size's density rows carrying the group's full-clear sum (all densities won)
/// or its n/N progress — and Basic's trifecta total under its three presets. Split
/// from `ScoreboardView` (which keeps the sheet chrome and filters) for the
/// type-body-length budget; not `private` because Swift `private` is file-scoped.
extension ScoreboardView {
    /// One header-plus-rows group of the filtered list. Grid/Hive group by SIZE
    /// (the sum stays comparable within one board scale); Basic is a single
    /// unlabelled group whose standing renders as a trailing Total row instead.
    struct ConfigGroup: Identifiable {
        let label: String?
        let configs: [GameConfig]
        var id: String { configs.first?.storageKey ?? "empty" }
    }

    /// The filtered leaf, grouped: Grid/Hive one group per size; Basic one group.
    static func groups(family: BoardFamily, edges: BoardEdges) -> [ConfigGroup] {
        switch family {
        case .basic:
            return [ConfigGroup(label: nil, configs: GameConfig.configs(family: .basic))]
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

    /// The group's full-clear standing from the live scoreboard.
    func standing(for group: ConfigGroup) -> FullClear.Standing {
        FullClear.standing(bests: group.configs.map { scoreboard.best(for: $0) })
    }

    /// The slim size subheader: size label leading, the full-clear sum (or n/N
    /// progress) trailing. Untouched sizes show just the label — a row of "0/5"
    /// noise would drown the list.
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
    /// while working toward it; nothing when untouched.
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
