import DonpaCore
import SwiftUI

/// The rivals row under the filters — the door to the Mess hall. (The
/// squad-scope menu that lived here is parked with squads; the comparison
/// always ranks all rivals.) An extension so it doesn't count against
/// `ScoreboardView`'s type-body-length budget.
extension ScoreboardView {
    @ViewBuilder var manageRivalsControl: some View {
        if let onMessHall {
            HStack(spacing: 8) {
                Spacer()
                Button(action: onMessHall) {
                    Text("Manage rivals", bundle: .module).font(.caption)
                }
                .modifier(zoneRing(.manage))
            }
            .padding(.horizontal, Self.rowInset)
        }
    }
}

extension ScoreboardView {
    /// The per-device reading, sync's sibling in the footer — only meaningful
    /// (and only shown) while the household view exists at all.
    @ViewBuilder var deviceScoresDoor: some View {
        if settings.syncScores {
            Button {
                showingDeviceScores = true
            } label: {
                Text("Scores by device", bundle: .module).font(.caption)
            }
            .modifier(zoneRing(.devices))
        }
    }
}
