import DonpaCore
import SwiftUI

/// The achievements grid: earned medals inked, unearned as silhouettes with
/// their rule, hidden feats a "?" until earned. The selected feat's detail line
/// renders under the grid, so the grid never reflows.
struct DecorationsSection: View {
    @ObservedObject var achievements: AchievementStore
    /// Merged score records, feeding the detail line's live stat value.
    let records: [String: ScoreRecord]
    let rowInset: CGFloat
    /// Hoisted to the host so keyboard browsing can drive it alongside taps.
    @Binding var selected: AchievementID?
    var keyFocusIndex: Int?
    /// The header is the keyboard zone's landing spot: Return/Space there
    /// toggles the fold, ↓ steps into the grid.
    var headerKeyFocused: Bool = false
    @Binding var collapsed: Bool
    var gcEnabled: Binding<Bool>?
    /// The footer toggle is the medals zone's last keyboard stop.
    var gcKeyFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !collapsed {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], spacing: 10
                ) {
                    ForEach(
                        Array(AchievementID.allCases.enumerated()), id: \.element
                    ) { index, id in
                        cell(id)
                            .modifier(FocusRing(focused: keyFocusIndex == index, inset: 1))
                    }
                }
                .padding(.horizontal, rowInset)
                if let selected { detail(selected) }
                if let gcEnabled { gameCenterFooter(gcEnabled) }
            }
        }
    }

    /// Opt-in reporting — Game Center never hears about the app until this is on.
    private func gameCenterFooter(_ binding: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: binding) {
                Text("Game Center", bundle: .module)
                    .font(.subheadline.weight(.medium))
            }
            .toggleStyle(.switch)
            #if os(iOS)
            .controlSize(.mini)
            #endif
            .fixedSize()
            Text(
                binding.wrappedValue
                    ? "Reporting to Game Center" : "Not reporting", bundle: .module
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .keyFocusRing(gcKeyFocused)
        .padding(.horizontal, rowInset)
    }

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { collapsed.toggle() }
        } label: {
            HStack(spacing: 8) {
                Text("Decorations", bundle: .module)
                    .font(.title3.bold())
                if collapsed {
                    Text(verbatim: "\(earnedCount)/\(AchievementID.allCases.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyFocusRing(headerKeyFocused)
        .padding(.horizontal, rowInset)
        .accessibilityLabel(Text("Decorations", bundle: .module))
        .accessibilityValue(collapsedA11yValue)
    }

    private var collapsedA11yValue: Text {
        guard collapsed else { return Text("expanded", bundle: .module) }
        return Text(
            "collapsed, \(earnedCount) of \(AchievementID.allCases.count) earned",
            bundle: .module)
    }

    private var earnedCount: Int {
        AchievementID.allCases.filter { achievements.earnedTier($0) > 0 }.count
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
            if !secret, let progress = AchievementEngine.progress(for: id, records: records) {
                progressLine(id: id, progress: progress)
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

    @ViewBuilder private func progressLine(id: AchievementID, progress: AchievementProgress)
        -> some View
    {
        let value = progressValueText(progress)
        let next = nextThresholdText(id: id, progress: progress)
        HStack(spacing: 4) {
            value.font(.caption.weight(.semibold))
            if let next {
                next.font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func progressValueText(_ progress: AchievementProgress) -> Text {
        let grouped = ScoreboardView.grouped(progress.current)
        switch progress.metric {
        case .wins:
            return Text("\(grouped) won", bundle: .module)
        case .tiles:
            return Text("\(grouped) tiles opened", bundle: .module)
        case .mines:
            return Text("\(grouped) disarmed", bundle: .module)
        case .bestSeconds:
            return Text(
                "Best \(TimeFormat.mmsst(centiseconds: progress.current))", bundle: .module)
        case .luckPercent:
            return Text("\(progress.current)% luckiest", bundle: .module)
        }
    }

    /// The next unearned rung for a count feat. Speed/luck run the other way
    /// (lower is better), so no number is teased there.
    private func nextThresholdText(id: AchievementID, progress: AchievementProgress) -> Text? {
        guard progress.metric == .wins || progress.metric == .tiles || progress.metric == .mines,
            let thresholds = id.tierThresholds,
            let next = thresholds.first(where: { $0 > progress.current })
        else { return nil }
        return Text("(next: \(ScoreboardView.grouped(next)))", bundle: .module)
    }
}
