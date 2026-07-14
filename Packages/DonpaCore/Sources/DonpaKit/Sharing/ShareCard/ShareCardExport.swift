import DonpaCore
import SwiftUI
import UniformTypeIdentifiers

/// Shares the branded QR card as a PNG — written to a temp file and shared by URL,
/// which both platforms' share sheets handle reliably (a bare in-memory image isn't).
struct ShareImageButton: View {
    let qr: Image
    let name: String
    /// Identity that changes with the QR (the share URL) — re-renders on edit.
    let linkID: URL
    /// Fired by the host to open the picker from the keyboard (macOS).
    var activate = Pulse()
    @State private var rendered: (image: PlatformImage, url: URL)?
    #if os(macOS)
    @State private var anchor = SharePickerButton.AnchorView()
    #endif

    var body: some View {
        // macOS drives NSSharingServicePicker instead of ShareLink so the keyboard
        // can open the same picker the click does (ShareLink isn't programmatic).
        #if os(macOS)
        Button {
            show()
        } label: {
            label
        }
        .disabled(rendered == nil)
        .background(SharePickerButton.AnchorRepresentable(view: anchor))
        .task(id: linkID) { rendered = await build() }
        .onPulse(activate) { show() }
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
#if os(macOS)
/// Saves the branded QR card as a PNG — macOS's share picker offers no save-to-disk
/// service, so the affordance must be the app's own.
struct SaveImageButton: View {
    let qr: Image
    let name: String
    /// Identity that changes with the QR (the share URL) — re-renders on edit.
    let linkID: URL
    /// Fired by the host to open the save panel from the keyboard.
    var activate = Pulse()

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
        .onPulse(activate) {
            guard png != nil else { return }
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
