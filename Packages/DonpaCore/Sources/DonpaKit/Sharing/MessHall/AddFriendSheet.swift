import DonpaCore
import SwiftUI

/// Scan-only by design: showing your own code lives on the Mess hall's inline
/// share card, so this sheet has no mode toggle.
struct AddFriendSheet: View {
    let onFound: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(iOS)
        NavigationStack {
            ScrollView { ScanContent(onFound: onFound).padding(20) }
                .navigationTitle(Text("Add rival", bundle: .module))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Cancel", bundle: .module)
                        }
                    }
                }
        }
        #else
        VStack(spacing: 16) {
            Text("Add rival", bundle: .module).font(.title2.bold())
            ScanContent(onFound: onFound)
            Button {
                dismiss()
            } label: {
                Text("Cancel", bundle: .module)
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(minWidth: 340)
        #endif
    }
}
