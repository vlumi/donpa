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
