import DonpaCore
import SwiftUI

/// The inline "share my scores" card — lives ON the Mess hall, not behind a sheet:
/// your name, career opt-in, the QR (the primary, in-person channel — matches the
/// trust model), and share/copy-link buttons, one glance away. The payload is built
/// from the MERGED cross-device view; when sync is on we refresh first, and either
/// way the footer says honestly whether it's your synced best or this device only.
struct ShareCardView: View {
    @ObservedObject var scoreboard: Scoreboard
    @ObservedObject var settings: Settings

    /// Minted lazily on first share; held for the card's lifetime.
    private let identityStore = ShareIdentityStore()

    @State private var name: String = ""
    @State private var includeCareer = false
    @State private var link: URL?
    @State private var qr: Image?
    @State private var failed = false

    var body: some View {
        // Compact: the QR sits beside the fields, so the card stays ~160pt tall and
        // the rivals list below keeps the room. The QR is still comfortably scannable
        // phone-to-phone at this size.
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField(text: $name) {
                        Text("Your name", bundle: .module)
                    }
                    .textFieldStyle(.roundedBorder)
                    .onChangeCompat(of: name) { _ in
                        settings.shareName = name
                        rebuild()
                    }
                    Toggle(isOn: $includeCareer) {
                        Text("Include career stats", bundle: .module)
                    }
                    .onChangeCompat(of: includeCareer) { _ in rebuild() }
                    if let link {
                        shareButtons(for: link)
                    }
                }
                .frame(maxWidth: .infinity)
                qrThumb
            }
            // Honest provenance: synced best vs. this device only.
            Text(provenanceKey, bundle: .module)
                .font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.primary.opacity(0.05))
        )
        .onAppear {
            if name.isEmpty { name = settings.shareName }
            rebuild()
        }
    }

    @ViewBuilder private var qrThumb: some View {
        if let qr {
            qr
                .interpolation(.none)  // keep QR modules crisp
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 132)
                .padding(8)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel(Text("Share QR code", bundle: .module))
        } else if failed {
            Text("Couldn't prepare your share.", bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 148, height: 148)
        } else {
            ProgressView().frame(width: 148, height: 148)
        }
    }

    /// Send the link (the system share sheet already offers Copy, so no separate
    /// copy button) plus share a branded QR IMAGE — the framed card, for posting
    /// where a bare link/QR has no context.
    @ViewBuilder private func shareButtons(for link: URL) -> some View {
        // Wraps to two rows when the column is narrow (compact phones).
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { shareButtonRow(for: link) }
            VStack(alignment: .leading, spacing: 8) { shareButtonRow(for: link) }
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder private func shareButtonRow(for link: URL) -> some View {
        ShareLinkButton(url: link)
        if let qr {
            // `link` keys the render: it changes whenever the QR does (name /
            // career edit), so the card image rebuilds to match.
            ShareImageButton(qr: qr, name: currentName, linkID: link)
        }
    }

    /// The name to stamp on the shared card — same trimmed input the payload used.
    private var currentName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The footer key: synced-across-devices vs. this-device-only, mirroring how the
    /// scoreboard footer labels sync state.
    private var provenanceKey: LocalizedStringKey {
        scoreboard.isCloudActive
            ? "These are your current best scores across all your devices."
            : "Sync is off — sharing this device's current scores only."
    }

    /// Rebuild the payload → QR + link. Refresh from cloud first when sync is active
    /// so the shared blob reflects the current cross-device best.
    private func rebuild() {
        failed = false
        if scoreboard.isCloudActive { scoreboard.refreshFromCloud() }
        // The name is the sharer's own input; the RECEIVER sanitizes on decode
        // (where it matters for safety). Just trim whitespace for a tidy payload.
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let identity = identityStore.identity(),
            let payload = SharePayloadBuilder.build(
                from: scoreboard, identity: identity,
                name: trimmed.isEmpty ? "?" : trimmed, includeCareer: includeCareer, now: Date()),
            let url = try? ShareLink.url(for: payload)
        else {
            qr = nil
            link = nil
            failed = true
            return
        }
        link = url
        qr = QRCode.image(from: url.absoluteString)
    }

}

/// A thin wrapper over SwiftUI's `ShareLink` (the system share sheet) so the call
/// site stays clean and cross-platform.
private struct ShareLinkButton: View {
    let url: URL
    var body: some View {
        ShareLink(item: url) {
            Label {
                Text("Share link", bundle: .module)
            } icon: {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }
}

/// Shares the branded QR card as a PNG. The rendered image is written to a temp file
/// once and shared by URL — reliable on both iOS and macOS share sheets (sharing a
/// bare in-memory image is fiddlier cross-platform).
private struct ShareImageButton: View {
    let qr: Image
    let name: String
    /// Identity that changes with the QR (the share URL) — re-renders on edit.
    let linkID: URL
    /// Rendered card image + its temp-file URL. Rebuilt when `linkID` changes;
    /// rendering on every body pass would be wasteful.
    @State private var rendered: (image: PlatformImage, url: URL)?

    var body: some View {
        Group {
            if let rendered {
                ShareLink(
                    item: rendered.url,
                    preview: SharePreview(previewTitle, image: previewImage(rendered.image))
                ) {
                    label
                }
            } else {
                label.opacity(0.5)
            }
        }
        .task(id: linkID) { rendered = await build() }
    }

    private var label: some View {
        Label {
            Text("Share image", bundle: .module)
        } icon: {
            Image(systemName: "photo")
        }
    }

    /// Render the branded card once, then write its PNG to a temp file. The card's date
    /// is "now" — the moment of sharing (matches the payload's `issuedAt` closely enough
    /// for a human-readable day stamp).
    @MainActor
    private func build() async -> (PlatformImage, URL)? {
        guard let image = ShareCard.render(qr: qr, name: name, date: Date()),
            let url = Self.writePNG(image)
        else { return nil }
        return (image, url)
    }

    private var previewTitle: String {
        String(localized: "Donpa Squad score share", bundle: .module)
    }

    private func previewImage(_ image: PlatformImage) -> Image {
        #if os(iOS)
        Image(uiImage: image)
        #elseif os(macOS)
        Image(nsImage: image)
        #endif
    }

    /// PNG bytes for the platform image → a temp file the share sheet can hand off.
    private static func writePNG(_ image: PlatformImage) -> URL? {
        guard let data = pngData(image) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("donpa-rival-share.png")
        return (try? data.write(to: url, options: .atomic)) == nil ? nil : url
    }

    private static func pngData(_ image: PlatformImage) -> Data? {
        #if os(iOS)
        return image.pngData()
        #elseif os(macOS)
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
        #endif
    }
}
