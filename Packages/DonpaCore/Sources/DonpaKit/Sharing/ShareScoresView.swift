import DonpaCore
import SwiftUI

/// "Share my scores" sheet: type a display name, optionally include career totals,
/// and get a QR (the primary, in-person channel — matches the trust model) plus a
/// copy/share link for remote sending. The payload is built from the MERGED
/// cross-device view; when sync is on we refresh first, and either way the footer
/// says honestly whether it's your synced best or this device only.
struct ShareScoresView: View {
    @ObservedObject var scoreboard: Scoreboard
    @ObservedObject var settings: Settings
    /// Open directly on the Scan tab (the Mess hall's "Add rival" door).
    var startInScanMode = false
    /// A scanned rival URL to route into the receive flow. The host closes this sheet
    /// and hands the URL to the root classify/prompt path (same as a tapped link).
    var onScanned: ((URL) -> Void)?
    @Environment(\.dismiss) private var dismiss

    /// Minted lazily on first share; held for the sheet's lifetime.
    private let identityStore = ShareIdentityStore()

    /// Show my QR to a rival, or scan a rival's. One sheet, two jobs.
    private enum Mode: Hashable { case show, scan }
    @State private var mode: Mode = .show

    @State private var name: String = ""
    @State private var includeCareer = false
    @State private var link: URL?
    @State private var qr: Image?
    @State private var failed = false

    var body: some View {
        chrome
            .onAppear {
                if startInScanMode { mode = .scan }
                if name.isEmpty { name = settings.shareName }
                rebuild()
            }
    }

    /// The mode switch + the active mode's body.
    @ViewBuilder private var content: some View {
        VStack(spacing: 16) {
            Picker(selection: $mode) {
                Text("Show", bundle: .module).tag(Mode.show)
                Text("Scan", bundle: .module).tag(Mode.scan)
            } label: {
                Text("Mode", bundle: .module)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            #if os(macOS)
            // ⌘1 / ⌘2 switch modes (standard macOS segment nav), via hidden buttons.
            .background {
                Group {
                    Button("") { mode = .show }.keyboardShortcut("1", modifiers: .command)
                    Button("") { mode = .scan }.keyboardShortcut("2", modifiers: .command)
                }
                .opacity(0)
            }
            #endif

            switch mode {
            case .show: showContent
            case .scan:
                ScanContent { url in
                    dismiss()
                    onScanned?(url)
                }
            }
        }
    }

    @ViewBuilder private var showContent: some View {
        VStack(spacing: 16) {
            // Name + career opt-in drive the payload; editing rebuilds the QR/link.
            VStack(alignment: .leading, spacing: 12) {
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
            }
            .padding(.horizontal, 4)

            if let qr {
                qr
                    .interpolation(.none)  // keep QR modules crisp
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260, maxHeight: 260)
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(Text("Share QR code", bundle: .module))
            } else if failed {
                Text("Couldn't prepare your share.", bundle: .module)
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(height: 260)
            } else {
                ProgressView().frame(height: 260)
            }

            if let link {
                shareButtons(for: link)
            }

            // Honest provenance: synced best vs. this device only.
            Text(provenanceKey, bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    /// Send the link (the system share sheet already offers Copy, so no separate
    /// copy button) plus share a branded QR IMAGE — the framed card, for posting
    /// where a bare link/QR has no context.
    @ViewBuilder private func shareButtons(for link: URL) -> some View {
        HStack(spacing: 12) {
            ShareLinkButton(url: link)
            if let qr {
                // `link` keys the render: it changes whenever the QR does (name /
                // career edit), so the card image rebuilds to match.
                ShareImageButton(qr: qr, name: currentName, linkID: link)
            }
        }
        .buttonStyle(.bordered)
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

    /// iOS NavigationStack + Done; macOS inline + Done, matching the other sheets.
    @ViewBuilder private var chrome: some View {
        #if os(iOS)
        NavigationStack {
            ScrollView { content.padding(20) }
                .navigationTitle(Text("Share", bundle: .module))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Done", bundle: .module)
                        }
                    }
                }
        }
        #else
        VStack(spacing: 16) {
            Text("Share", bundle: .module).font(.title2.bold())
            content
            Button {
                dismiss()
            } label: {
                Text("Done", bundle: .module)
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(minWidth: 340)
        #endif
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
