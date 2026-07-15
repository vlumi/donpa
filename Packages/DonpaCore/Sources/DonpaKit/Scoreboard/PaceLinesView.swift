import DonpaCore
import SwiftUI

/// The career's pace ladder lines: one figure per family × edges × density,
/// lit only once every gate size (XS–L; Drills its full range) has a logged
/// win — see `Pace.ladderPace`. Only lit lines render; until any exists, one
/// caption says how to light the first.
struct PaceLinesView: View {
    @ObservedObject var scoreboard: Scoreboard
    let rowInset: CGFloat

    private struct Line: Identifiable {
        let id: String
        let label: String
        let pace: Double
    }

    private var lines: [Line] {
        let records = scoreboard.displayRecords
        var result: [Line] = []
        for family in BoardFamily.allCases {
            switch family {
            case .basic:
                continue
            case .practice:
                if let pace = Pace.ladderPace(
                    records: records, family: .practice, density: nil, edges: .flat)
                {
                    result.append(Line(id: "practice", label: family.label, pace: pace))
                }
            case .grid, .hive:
                for edges in BoardEdges.allCases {
                    for density in Density.allCases {
                        guard
                            let pace = Pace.ladderPace(
                                records: records, family: family, density: density,
                                edges: edges)
                        else { continue }
                        var label = "\(family.label) · \(density.label)"
                        if edges == .round { label += " · \(edges.label)" }
                        result.append(
                            Line(id: "\(family)|\(edges)|\(density)", label: label, pace: pace))
                    }
                }
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pace", bundle: .module)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if lines.isEmpty {
                Text(
                    "Win every size up to L on one board type to light its pace line.",
                    bundle: .module
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ForEach(lines) { line in
                    HStack {
                        Text(verbatim: line.label).font(.callout)
                        Spacer()
                        Text(verbatim: PaceText.display(line.pace))
                            .font(.callout.weight(.semibold))
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.horizontal, rowInset)
    }
}
