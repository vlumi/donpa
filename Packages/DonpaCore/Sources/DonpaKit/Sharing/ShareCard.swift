import DonpaCore
import SwiftUI

/// A branded, shareable card wrapping the QR — for sending to a chat / posting, where
/// a bare QR bitmap has no context. The app's boot-mark + "Donpa Squad", the QR, the
/// sharer's name, and a call to action, in the app's B&W look. Rendered to an image by
/// `ShareCard.render` and offered via the Share sheet's "Share image".
struct ShareCard: View {
    let qr: Image
    let name: String

    /// Fixed layout so the rendered image is consistent regardless of where it's built.
    static let size = CGSize(width: 320, height: 420)

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image("BootPrint", bundle: .module)
                    .resizable().scaledToFit().frame(width: 26, height: 26)
                Text("Donpa Squad", bundle: .module)
                    .font(.title3.bold())
            }

            qr
                .interpolation(.none)  // crisp modules
                .resizable().scaledToFit()
                .frame(width: 220, height: 220)
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))

            if !name.isEmpty {
                Text(verbatim: name).font(.headline).lineLimit(1)
            }
            Text("Scan to add me as a rival", bundle: .module)
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(white: 0.11))
        .foregroundStyle(.white)
    }

    /// Render the card to a platform image at 3× for a sharp export. `@MainActor`
    /// because `ImageRenderer` walks the SwiftUI view.
    @MainActor
    static func render(qr: Image, name: String) -> PlatformImage? {
        let renderer = ImageRenderer(content: ShareCard(qr: qr, name: name))
        renderer.scale = 3
        #if os(iOS)
        return renderer.uiImage
        #elseif os(macOS)
        return renderer.nsImage
        #endif
    }
}

#if os(iOS)
typealias PlatformImage = UIImage
#elseif os(macOS)
typealias PlatformImage = NSImage
#endif
