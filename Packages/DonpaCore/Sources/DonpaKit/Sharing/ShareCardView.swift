import DonpaCore
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var link: URL?
    @State private var qr: Image?
    @State private var failed = false
    /// The full-size QR overlay (compact layouts show a thumb too dense to scan).
    @State private var enlarged = false
    /// Measured card width → picks the inline QR size (see `qrSize`).
    @State private var cardWidth: CGFloat = 0

    /// The share payload is DENSE (signed + every board's best), so small renders
    /// don't resolve in a scanner. Wide layouts (Mac, iPad) get a directly-scannable
    /// size inline; compact ones keep a thumb and rely on tap-to-enlarge.
    private var qrSize: CGFloat { cardWidth >= 480 ? 240 : 132 }

    var body: some View {
        // The QR sits beside the fields so the card stays shallow and the rivals
        // list below keeps the room. Tapping the QR opens it full size.
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
                    Toggle(isOn: $settings.shareIncludeCareer) {
                        Text("Include career stats", bundle: .module)
                            // Wrap on a narrow column instead of truncating to
                            // "Include care…".
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .onChangeCompat(of: settings.shareIncludeCareer) { _ in rebuild() }
                    if let link {
                        shareButtons(for: link)
                    } else if trimmedName.isEmpty {
                        // A nameless card would go out stamped "?" — a poor first
                        // handshake in a name-is-identity model. Nudge, don't ship it.
                        Text("Add your name to share.", bundle: .module)
                            .font(.caption).foregroundStyle(.secondary)
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
        // Measure the card's width to size the inline QR (no GeometryReader wrapper —
        // it would fight the card's natural height).
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { cardWidth = geo.size.width }
                    .onChangeCompat(of: geo.size.width) { cardWidth = $0 }
            }
        )
        .sheet(isPresented: $enlarged) { QRZoomSheet(qr: qr) }
        .onAppear {
            // Pull the latest synced name (iCloud Keychain has no change
            // notifications, so opening the card is the refresh point) BEFORE
            // seeding the field from it.
            settings.reconcileShareName()
            if name.isEmpty { name = settings.shareName }
            rebuild()
        }
    }

    @ViewBuilder private var qrThumb: some View {
        if let qr {
            Button {
                enlarged = true
            } label: {
                qr
                    .interpolation(.none)  // keep QR modules crisp
                    .resizable()
                    .scaledToFit()
                    .frame(width: qrSize, height: qrSize)
                    .padding(8)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10))
                    // The "this grows" hint, tucked on the corner of the plate.
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(.black.opacity(0.55), in: Circle())
                            .padding(5)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Share QR code", bundle: .module))
            .accessibilityHint(Text("Shows the code full size.", bundle: .module))
        } else if failed {
            Text("Couldn't prepare your share.", bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 148, height: 148)
        } else if trimmedName.isEmpty {
            // Awaiting a name — the nudge under the field carries the message;
            // a placeholder plate keeps the card's shape steady.
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
                .frame(width: qrSize, height: qrSize)
                .overlay {
                    Image(systemName: "qrcode")
                        .font(.largeTitle).foregroundStyle(.tertiary)
                }
                .accessibilityHidden(true)
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
            ShareImageButton(qr: qr, name: trimmedName, linkID: link)
            #if os(macOS)
            // macOS's share picker has NO save-to-disk service (iOS's sheet offers
            // "Save to Files"), so saving the card is its own button + save panel.
            SaveImageButton(qr: qr, name: trimmedName, linkID: link)
            #endif
        }
    }

    /// The trimmed name: stamped on the card, and (when empty) the gate that
    /// suppresses sharing so no "?" card ever goes out.
    private var trimmedName: String {
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
        // No name → no card. The QR/buttons stay hidden and the field shows a nudge;
        // a "?" card is a bad first handshake when the name IS the shared identity.
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            qr = nil
            link = nil
            return
        }
        if scoreboard.isCloudActive { scoreboard.refreshFromCloud() }
        // The name is the sharer's own input; the RECEIVER sanitizes on decode
        // (where it matters for safety). The trim above is just for a tidy payload.
        guard let identity = identityStore.identity(),
            let payload = SharePayloadBuilder.build(
                from: scoreboard, identity: identity, name: trimmed,
                includeCareer: settings.shareIncludeCareer, now: Date()),
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

/// The QR at scanning size: near the full sheet width on iOS, a generous fixed
/// square on macOS. Tap anywhere (or Close) to dismiss.
private struct QRZoomSheet: View {
    let qr: Image?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Close", bundle: .module)
                }
                .keyboardShortcut(.cancelAction)
            }
            if let qr {
                qr
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 480)
                    .padding(20)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel(Text("Share QR code", bundle: .module))
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 620)
        #endif
    }
}

#if os(macOS)
/// Saves the branded QR card as a PNG via the system save panel — macOS's share
/// picker offers no save-to-disk service, so the affordance must be the app's own.
private struct SaveImageButton: View {
    let qr: Image
    let name: String
    /// Identity that changes with the QR (the share URL) — re-renders on edit.
    let linkID: URL

    @State private var png: Data?
    @State private var exporting = false

    var body: some View {
        Button {
            exporting = true
        } label: {
            Label {
                Text("Save image", bundle: .module)
            } icon: {
                Image(systemName: "square.and.arrow.down")
            }
        }
        .disabled(png == nil)
        .task(id: linkID) { png = await render() }
        .fileExporter(
            isPresented: $exporting,
            document: PNGDocument(data: png ?? Data()),
            contentType: .png,
            defaultFilename: "donpa-scores"
        ) { _ in }
    }

    @MainActor
    private func render() async -> Data? {
        guard let image = ShareCard.render(qr: qr, name: name, date: Date()),
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// A PNG payload for `fileExporter`.
private struct PNGDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#endif
