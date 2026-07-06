import DonpaCore
import SwiftUI

/// The career's Breakdown block: how play spreads across family / size / density,
/// as proportion bars, toggling between playtime and game count. A view over
/// `PlayDistribution` — no new collection, just the per-config records re-sliced.
/// Single-accent segments (an opacity ramp) with the legend carrying the labels
/// and percentages, so color never carries information alone.
struct PlayDistributionView: View {
    @ObservedObject var scoreboard: Scoreboard
    /// Shared horizontal inset (matches the stat rows).
    let rowInset: CGFloat

    @State private var metric: PlayDistribution.Metric = .playtime

    var body: some View {
        let entries = Self.entries(from: scoreboard)
        let axes = PlayDistribution.Axis.allCases.map {
            (axis: $0, shares: PlayDistribution.shares(entries: entries, metric: metric, axis: $0))
        }
        if axes.contains(where: { !$0.shares.isEmpty }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Breakdown", bundle: .module)
                        .font(.headline)
                    Spacer()
                    Picker(selection: $metric) {
                        Text("Playtime", bundle: .module).tag(PlayDistribution.Metric.playtime)
                        Text("Games", bundle: .module).tag(PlayDistribution.Metric.games)
                    } label: {
                        Text("Breakdown", bundle: .module)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                ForEach(axes, id: \.axis) { axis, shares in
                    if !shares.isEmpty {
                        bar(label: Self.title(for: axis), shares: shares)
                    }
                }
            }
            .padding(.horizontal, rowInset)
        }
    }

    /// Every config's games + playtime off its record (unplayed configs contribute
    /// nothing and are dropped by the aggregation).
    static func entries(from scoreboard: Scoreboard) -> [PlayDistribution.Entry] {
        var configs = GameConfig.configs(family: .basic)
        for family in [BoardFamily.grid, .hive] {
            for edges in BoardEdges.allCases {
                configs += GameConfig.configs(family: family, edges: edges)
            }
        }
        return configs.compactMap { config in
            guard let record = scoreboard.record(for: config) else { return nil }
            return PlayDistribution.Entry(
                config: config,
                games: record.gamesPlayed.total,
                playtimeCentiseconds: record.playtimeCentiseconds.total)
        }
    }

    private static func title(for axis: PlayDistribution.Axis) -> LocalizedStringKey {
        switch axis {
        case .family: return "Family"
        case .size: return "Size"
        case .density: return "Density"
        }
    }

    /// One axis: caption label, the proportion bar, and the legend line.
    private func bar(label: LocalizedStringKey, shares: [PlayDistribution.Share]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label, bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(Array(shares.enumerated()), id: \.offset) { index, share in
                        Rectangle()
                            .fill(Color.accentColor.opacity(Self.ramp(index, of: shares.count)))
                            .frame(width: max(1, geo.size.width * share.fraction))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 10)
            // The legend carries the actual information; the bar is the shape of it.
            Text(verbatim: legend(shares))
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: legend(shares)))
    }

    /// Whole-percent legend: "Grid 52% · Hive 31% · Basic 17%", axis order. A real
    /// but sub-half-percent share reads "<1%", never a dishonest "0%".
    private func legend(_ shares: [PlayDistribution.Share]) -> String {
        shares.map { share in
            let percent = share.fraction * 100
            let text = percent < 0.5 ? "<1" : "\(Int(percent.rounded()))"
            return "\(share.label) \(text)%"
        }.joined(separator: " · ")
    }

    /// Opacity ramp for the single-accent segments — distinct steps, first (leading)
    /// strongest. Labels, not color, carry the meaning.
    private static func ramp(_ index: Int, of count: Int) -> Double {
        guard count > 1 else { return 0.85 }
        let step = 0.7 / Double(count - 1)
        return 0.85 - Double(index) * step
    }
}
