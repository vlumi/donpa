import DonpaCore
import SwiftUI

#if os(iOS)
/// The Service Record's iOS nav-bar items — Share (QR + scan), Rivals, Done. Reset
/// moved to Settings; Scan folded into the Share sheet — so the title stops truncating
/// on SE. Split into an extension so it doesn't count against `ScoreboardView`'s
/// type-body-length budget (mirrors `ScoreFormatting`).
extension ScoreboardView {
    @ToolbarContentBuilder var iOSToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                sharing = true
            } label: {
                Label {
                    Text("Share", bundle: .module)
                } icon: {
                    // A QR glyph, not the generic share arrow — the sheet is about
                    // exchanging QR codes (show yours / scan a rival's), not the system
                    // share sheet.
                    Image(systemName: "qrcode")
                }
            }
            .accessibilityIdentifier("scoreboard.share")
        }
        if let onFriends {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onFriends) {
                    Label {
                        Text("Rivals", bundle: .module)
                    } icon: {
                        Image(systemName: "person.2")
                    }
                }
                .accessibilityIdentifier("scoreboard.friends")
            }
        }
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
