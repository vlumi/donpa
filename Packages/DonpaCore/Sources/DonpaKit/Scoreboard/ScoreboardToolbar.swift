import DonpaCore
import SwiftUI

#if os(iOS)
/// The Service Record's iOS nav-bar items — an extension so they don't count
/// against `ScoreboardView`'s type-body-length budget.
extension ScoreboardView {
    @ToolbarContentBuilder var iOSToolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button {
                dismiss()
            } label: {
                Text("Done", bundle: .module)
            }
            .accessibilityIdentifier("sheet.done")
        }
    }
}
#endif
