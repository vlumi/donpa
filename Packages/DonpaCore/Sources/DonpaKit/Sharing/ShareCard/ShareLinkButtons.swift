import DonpaCore
import SwiftUI

// The share-LINK buttons: the system share sheet, per platform.
#if os(macOS)
/// The share-link button, macOS: drives `NSSharingServicePicker` from an
/// anchored view — SwiftUI's `ShareLink` can't be invoked programmatically,
/// and the keyboard's Return needs to open the same picker the click does.
struct SharePickerButton: View {
    let url: URL
    var activate = Pulse()
    @State private var anchor = AnchorView()

    var body: some View {
        Button {
            show()
        } label: {
            Label {
                Text("Share link", bundle: .module)
            } icon: {
                Image(systemName: "square.and.arrow.up")
            }
            .frame(maxWidth: .infinity)
        }
        .background(AnchorRepresentable(view: anchor))
        .onPulse(activate) { show() }
    }

    private func show() {
        NSSharingServicePicker(items: [url])
            .show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    final class AnchorView: NSView {}
    struct AnchorRepresentable: NSViewRepresentable {
        let view: AnchorView
        func makeNSView(context: Context) -> AnchorView { view }
        func updateNSView(_ nsView: AnchorView, context: Context) {}
    }
}
#endif

/// A thin wrapper over SwiftUI's `ShareLink` (the system share sheet) so the call
/// site stays clean and cross-platform. Stretches to fill its slot in the
/// share-actions row.
struct ShareLinkButton: View {
    let url: URL
    var body: some View {
        ShareLink(item: url) {
            Label {
                Text("Share link", bundle: .module)
            } icon: {
                Image(systemName: "square.and.arrow.up")
            }
            .frame(maxWidth: .infinity)
        }
    }
}
