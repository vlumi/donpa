import DonpaCore
import SwiftUI

#if os(iOS)
/// The Service Record's iOS nav-bar items — Share, Add friend (QR), Reset, Done.
/// Split into an extension so it doesn't count against `ScoreboardView`'s
/// type-body-length budget (mirrors `ScoreFormatting`).
extension ScoreboardView {
    @ToolbarContentBuilder var iOSToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                sharing = true
            } label: {
                Label {
                    Text("Share scores", bundle: .module)
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            .accessibilityIdentifier("scoreboard.share")
        }
        if let onScan {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onScan) {
                    Label {
                        Text("Add rival", bundle: .module)
                    } icon: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                }
                .accessibilityIdentifier("scoreboard.scan")
            }
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
        ToolbarItem(placement: .destructiveAction) {
            Button(role: .destructive) {
                confirmingReset = true
            } label: {
                Text("Reset", bundle: .module)
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
