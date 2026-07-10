import DonpaCore
import SwiftUI
import UniformTypeIdentifiers

/// The inline "share my scores" card — lives ON the Mess hall, not behind a sheet:
/// your name, career opt-in, and the sharing actions. **Nearby is the promoted
/// default** (the two-way, in-the-room swap); the remote channels sit on a
/// secondary row — link, and the QR behind a button (Nearby covers in-person
/// now, so the code no longer earns a permanent inline pane) whose full-size
/// view also carries the branded-card image exports. The payload is built from
/// the MERGED cross-device view; when sync is on we refresh first, and either
/// way the footer says honestly whether it's your synced best or this device
/// only.
struct ShareCardView: View {
    @ObservedObject var scoreboard: Scoreboard
    @ObservedObject var settings: Settings
    /// Open the Nearby exchange — the promoted, in-person path. The host owns the
    /// sheet (it also receives the swapped card); the card owns the gate: the
    /// button only shows once a name has produced a shareable link.
    var onNearby: (() -> Void)?

    /// Minted lazily on first share; held for the card's lifetime.
    private let identityStore = ShareIdentityStore()

    @State private var name: String = ""
    @State private var link: URL?
    @State private var qr: Image?
    @State private var failed = false
    /// The full-size QR sheet (behind the "QR code" button).
    @State private var enlarged = false

    var body: some View {
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
                shareActions(for: link)
            } else if trimmedName.isEmpty {
                // A nameless card would go out stamped "?" — a poor first
                // handshake in a name-is-identity model. Nudge, don't ship it.
                Text("Add your name to share.", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
            } else if failed {
                Text("Couldn't prepare your share.", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
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
        .sheet(isPresented: $enlarged) {
            QRZoomSheet(qr: qr, name: trimmedName, link: link)
        }
        .onAppear {
            // Pull the latest synced name (iCloud Keychain has no change
            // notifications, so opening the card is the refresh point) BEFORE
            // seeding the field from it.
            settings.reconcileShareName()
            if name.isEmpty { name = settings.shareName }
            rebuild()
        }
    }

    /// All the share actions, ONE row when it fits: Nearby (the promoted default)
    /// at half the width, the remote channels a quarter each — two flexible
    /// siblings split the row 50/50 and the remote pair halves its side. Narrow
    /// layouts (compact phones) stack Nearby above the remote pair instead.
    @ViewBuilder private func shareActions(for link: URL) -> some View {
        if onNearby != nil {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    nearbyButton
                    remoteButtons(for: link).frame(maxWidth: .infinity)
                }
                VStack(spacing: 8) {
                    nearbyButton
                    remoteButtons(for: link)
                }
            }
        } else {
            remoteButtons(for: link)
        }
    }

    @ViewBuilder private var nearbyButton: some View {
        if let onNearby {
            Button(action: onNearby) {
                Label {
                    Text("Nearby", bundle: .module)
                } icon: {
                    Image(systemName: "person.line.dotted.person.fill")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// The remote channels: send the link (the system share sheet already offers
    /// Copy, so no separate copy button) and show the QR full size — the
    /// branded-card image exports (share/save) live inside the QR view, beside
    /// the code they render.
    private func remoteButtons(for link: URL) -> some View {
        HStack(spacing: 8) {
            ShareLinkButton(url: link)
            if qr != nil {
                Button {
                    enlarged = true
                } label: {
                    Label {
                        Text("QR code", bundle: .module)
                    } icon: {
                        Image(systemName: "qrcode")
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityHint(Text("Shows the code full size.", bundle: .module))
            }
        }
        .buttonStyle(.bordered)
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
/// site stays clean and cross-platform. Stretches to fill its slot in the
/// share-actions row.
private struct ShareLinkButton: View {
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
/// square on macOS. The branded-card image exports (share/save) sit on the top
/// row — they render exactly what's shown, so they live beside it. Tap anywhere
/// (or Close) to dismiss.
private struct QRZoomSheet: View {
    let qr: Image?
    /// Stamped on the exported card image.
    let name: String
    /// Keys the exported-card render — it changes whenever the QR does.
    let link: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 8) {
                if let qr, let link {
                    Group {
                        ShareImageButton(qr: qr, name: name, linkID: link)
                        #if os(macOS)
                        // macOS's share picker has NO save-to-disk service (iOS's
                        // sheet offers "Save to Files"), so saving the card is its
                        // own button + save panel.
                        SaveImageButton(qr: qr, name: name, linkID: link)
                        #endif
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Close", bundle: .module)
                }
                .keyboardShortcut(.cancelAction)
            }
            if let qr {
                // The QR plate is the flexible element in BOTH axes: scaledToFit
                // keeps the code square while it fills whatever the sheet offers,
                // so resizing works in every direction and there's no dead space
                // (a fixed 480pt width cap + a bottom Spacer made the sheet
                // stretch only downward, into an empty gap).
                qr
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(20)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(Text("Share QR code", bundle: .module))
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(20)
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        #if os(macOS)
        // Ideal, not floor: a hard 620 minHeight pushed the code offscreen on
        // scaled ("larger text") displays. The QR is scaledToFit, so it shrinks
        // with the sheet — smaller than ~440pt it drops below comfortable
        // direct-scan density, but every control stays reachable and the sheet
        // can always be grown. The ideal is square-ish: the top row + paddings
        // eat ~90pt, so the plate lands near 520×510.
        .frame(minWidth: 480, idealWidth: 560, minHeight: 420, idealHeight: 600)
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
