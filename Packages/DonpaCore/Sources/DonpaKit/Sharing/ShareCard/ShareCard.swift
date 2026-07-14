import DonpaCore
import SwiftUI

/// The branded QR card, rendered to an image by `render` for the "Share image" export.
struct ShareCard: View {
    let qr: Image
    let name: String
    let date: Date

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
                .interpolation(.none)
                .resizable().scaledToFit()
                .frame(width: 220, height: 220)
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))

            if !name.isEmpty {
                Text(verbatim: name).font(.headline).lineLimit(1)
            }
            Text(verbatim: date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(white: 0.11))
        .foregroundStyle(.white)
    }

    @MainActor
    static func render(qr: Image, name: String, date: Date) -> PlatformImage? {
        let renderer = ImageRenderer(content: ShareCard(qr: qr, name: name, date: date))
        renderer.scale = 3
        #if os(iOS)
        return renderer.uiImage
        #elseif os(macOS)
        return renderer.nsImage
        #endif
    }
}
