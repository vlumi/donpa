import DonpaCore
import SwiftUI
import UniformTypeIdentifiers

// The share card's action machinery — the platform share buttons, the
// branded-image export buttons, and the QR zoom sheet — split from
// ShareCardView for the file-length budget.
#if os(macOS)
/// The share-link button, macOS: drives `NSSharingServicePicker` from an
/// anchored view — SwiftUI's `ShareLink` can't be invoked programmatically,
/// and the keyboard's Return needs to open the same picker the click does.
struct SharePickerButton: View {
    let url: URL
    var activateTick: Int = 0
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
        .onChangeCompat(of: activateTick) { _ in
            guard activateTick > 0 else { return }
            show()
        }
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

/// Shares the branded QR card as a PNG. The rendered image is written to a temp file
/// once and shared by URL — reliable on both iOS and macOS share sheets (sharing a
/// bare in-memory image is fiddlier cross-platform).
struct ShareImageButton: View {
    let qr: Image
    let name: String
    /// Identity that changes with the QR (the share URL) — re-renders on edit.
    let linkID: URL
    /// Bumped by the host to open the picker from the keyboard (macOS).
    var activateTick: Int = 0
    /// Rendered card image + its temp-file URL. Rebuilt when `linkID` changes;
    /// rendering on every body pass would be wasteful.
    @State private var rendered: (image: PlatformImage, url: URL)?
    #if os(macOS)
    @State private var anchor = SharePickerButton.AnchorView()
    #endif

    var body: some View {
        // macOS drives NSSharingServicePicker instead of ShareLink so the
        // keyboard's Space opens the same picker the click does (ShareLink
        // can't be invoked programmatically).
        #if os(macOS)
        Button {
            show()
        } label: {
            label
        }
        .disabled(rendered == nil)
        .background(SharePickerButton.AnchorRepresentable(view: anchor))
        .task(id: linkID) { rendered = await build() }
        .onChangeCompat(of: activateTick) { _ in
            guard activateTick > 0 else { return }
            show()
        }
        #else
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
        #endif
    }

    #if os(macOS)
    private func show() {
        guard let rendered else { return }
        NSSharingServicePicker(items: [rendered.url])
            .show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }
    #endif

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
/// square on macOS. The branded-card image exports (share/save) render exactly
/// what's shown, so they live beside it, in the footer with the standard
/// bottom-right Done. Tap anywhere (or Done) to dismiss.
struct QRZoomSheet: View {
    let qr: Image?
    /// Stamped on the exported card image.
    let name: String
    /// Keys the exported-card render — it changes whenever the QR does.
    let link: URL?
    @Environment(\.dismiss) private var dismiss
    /// The keyboard-focused export button (macOS): 0 share, 1 save.
    @State private var keyIndex: Int?
    @State private var shareTick = 0
    @State private var saveTick = 0

    var body: some View {
        VStack(spacing: 20) {
            if let qr {
                // Flexible in both axes (scaledToFit keeps the code square), so
                // the plate fills the sheet with no dead space.
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
            footer
        }
        .padding(20)
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .background(zoomKeyCatcher)
        #if os(macOS)
        // Low floors so small scaled-display screens can shrink it (the QR
        // scales down), capped at the ideal: macOS won't resize a sheet's width,
        // so extra height would only add dead space around the square code. The
        // ideal lands the plate near-square (~520pt), well above scan density.
        .frame(
            minWidth: 480, idealWidth: 560, maxWidth: 560,
            minHeight: 420, idealHeight: 600, maxHeight: 600)
        #endif
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let qr, let link {
                Group {
                    ShareImageButton(qr: qr, name: name, linkID: link, activateTick: shareTick)
                        .modifier(FocusRing(focused: keyIndex == 0, inset: 2))
                    #if os(macOS)
                    // macOS's share picker has NO save-to-disk service (iOS's
                    // sheet offers "Save to Files"), so saving the card is its
                    // own button + save panel.
                    SaveImageButton(qr: qr, name: name, linkID: link, activateTick: saveTick)
                        .modifier(FocusRing(focused: keyIndex == 1, inset: 2))
                    #endif
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Done", bundle: .module)
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    /// Arrows/Tab move between the export buttons; Return and Space press the
    /// focused one, Return with none focused is the default — Done. Esc
    /// dismisses (the catcher owns keyDown, so it's routed here).
    @ViewBuilder private var zoomKeyCatcher: some View {
        #if os(macOS)
        KeyCatcher { key in
            switch key {
            case .tab, .right, .down: moveFocus(1)
            case .backTab, .left, .up: moveFocus(-1)
            case .space: activateFocused()
            case .enter:
                if keyIndex == nil { dismiss() } else { activateFocused() }
            case .escape: dismiss()
            default: break
            }
        }
        #endif
    }

    #if os(macOS)
    private func activateFocused() {
        if keyIndex == 0 { shareTick += 1 }
        if keyIndex == 1 { saveTick += 1 }
    }
    #endif

    #if os(macOS)
    private func moveFocus(_ delta: Int) {
        guard qr != nil, link != nil else { return }
        guard let current = keyIndex else {
            keyIndex = 0
            return
        }
        keyIndex = (current + delta + 2) % 2
    }
    #endif
}

#if os(macOS)
/// Saves the branded QR card as a PNG via the system save panel — macOS's share
/// picker offers no save-to-disk service, so the affordance must be the app's own.
struct SaveImageButton: View {
    let qr: Image
    let name: String
    /// Identity that changes with the QR (the share URL) — re-renders on edit.
    let linkID: URL
    /// Bumped by the host to open the save panel from the keyboard.
    var activateTick: Int = 0

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
        .onChangeCompat(of: activateTick) { _ in
            guard activateTick > 0, png != nil else { return }
            exporting = true
        }
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
struct PNGDocument: FileDocument {
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
