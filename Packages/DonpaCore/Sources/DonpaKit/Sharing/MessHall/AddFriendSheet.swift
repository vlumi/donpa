import DonpaCore
import SwiftUI

/// Scan-only by design: showing your own code lives on the Mess hall's inline
/// share card, so this sheet has no mode toggle.
struct AddFriendSheet: View {
    let onFound: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetScaffold("Add rival", dismissStyle: .cancel, macMinWidth: 340) {
            #if os(iOS)
            ScrollView { ScanContent(onFound: onFound).padding(20) }
            #else
            ScanContent(onFound: onFound)
            #endif
        }
    }
}
