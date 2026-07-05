import DonpaCore
import SwiftUI

#if os(iOS)
/// The Service Record's iOS nav-bar items — just Done now: Share and Rivals moved to
/// the Mess hall (the Record keeps only the comparison views + the Manage-rivals
/// cross-link by the scope control). Split into an extension so it doesn't count
/// against `ScoreboardView`'s type-body-length budget (mirrors `ScoreFormatting`).
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
