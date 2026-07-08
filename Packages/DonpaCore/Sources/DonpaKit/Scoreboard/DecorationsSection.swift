import DonpaCore
import SwiftUI

/// The achievements grid in the Service Record (A4 of the progression spec):
/// every feat as a medal — earned inked (tier metals on the tiered ones),
/// unearned as a silhouette with its rule, hidden as a "?" until earned. One
/// tap opens the feat's detail line under the grid (fixed placement, so the
/// grid never reflows).
struct DecorationsSection: View {
    @ObservedObject var achievements: AchievementStore
    let rowInset: CGFloat

    @State private var selected: AchievementID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Decorations", bundle: .module)
                .font(.title3.bold())
                .padding(.horizontal, rowInset)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], spacing: 10) {
                ForEach(AchievementID.allCases, id: \.self) { id in
                    cell(id)
                }
            }
            .padding(.horizontal, rowInset)
            if let selected { detail(selected) }
        }
    }

    private func cell(_ id: AchievementID) -> some View {
        let tier = achievements.earnedTier(id)
        let secret = id.isHidden && tier == 0
        return Button {
            selected = selected == id ? nil : id
        } label: {
            VStack(spacing: 2) {
                MedalView(id: id, earnedTier: tier, size: 48)
                Text(verbatim: secret ? "???" : id.title)
                    .font(.caption2)
                    .foregroundStyle(tier > 0 ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            secret ? Text("Hidden decoration", bundle: .module) : Text(verbatim: id.title)
        )
        .accessibilityValue(value(for: id, tier: tier))
        .accessibilityAddTraits(selected == id ? [.isSelected] : [])
    }

    /// The spoken state: earned (+ tier count on tiered feats) or the rule.
    private func value(for id: AchievementID, tier: Int) -> Text {
        if tier > 0 {
            if let thresholds = id.tierThresholds {
                return Text("Earned, tier \(tier) of \(thresholds.count)", bundle: .module)
            }
            return Text("Earned", bundle: .module)
        }
        return id.isHidden
            ? Text("Earn it to reveal it.", bundle: .module)
            : Text(verbatim: id.featDescription)
    }

    /// The tapped feat's rule + earned date, under the grid.
    private func detail(_ id: AchievementID) -> some View {
        let tier = achievements.earnedTier(id)
        let secret = id.isHidden && tier == 0
        return VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: secret ? "???" : id.title)
                .font(.subheadline.bold())
            if secret {
                Text("Earn it to reveal it.", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(verbatim: id.featDescription)
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let date = achievements.firstEarned(id, tier: max(tier, 1)), tier > 0 {
                Text(
                    "Earned \(date.formatted(date: .abbreviated, time: .omitted))",
                    bundle: .module
                )
                .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, rowInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
