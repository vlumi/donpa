import SwiftUI

/// The one-time continue-or-fork prompt for a migrated install (see
/// DeviceIdentity): a restored/transferred install keeps counting as the old
/// device (a clean takeover), or — when the old device stays in use — starts
/// fresh with its own tally via the staged fork.
struct MigrationPrompt: ViewModifier {
    /// Seeded from the launch verdict — self-contained, shown at most once.
    @State private var isPresented = DeviceIdentity.launchVerdict == .migrated

    func body(content: Content) -> some View {
        content.alert(
            Text("Is this a new device?", bundle: .module),
            isPresented: $isPresented
        ) {
            Button {
                DeviceIdentity.continueAsBefore()
            } label: {
                Text("Continue as before", bundle: .module)
            }
            Button(role: .destructive) {
                DeviceIdentity.stageFork()
            } label: {
                Text("Start fresh", bundle: .module)
            }
        } message: {
            Text(
                """
                Donpa's data arrived from another device. If you still use \
                that device too, start fresh — this device gets its own \
                tally (nothing already earned is lost). Otherwise continue \
                as before. Starting fresh takes effect when you next open \
                Donpa.
                """, bundle: .module)
        }
    }
}
