import DonpaCore
import SwiftUI

#if os(macOS)
/// Drives `NSSharingServicePicker` from an anchored view — `ShareLink` can't be
/// invoked programmatically, and the keyboard's Return must open the same picker.
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
