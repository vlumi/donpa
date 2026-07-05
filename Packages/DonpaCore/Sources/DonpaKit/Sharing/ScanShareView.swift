import CoreImage
import DonpaCore
import SwiftUI

#if os(macOS)
import UniformTypeIdentifiers
#endif

/// The "add a friend by QR" sheet. iOS scans live with the camera; macOS (no
/// built-in scan target and often no camera) imports an image of a QR and decodes
/// it. Either way the decoded string is handed to `onFound` — the receive flow then
/// verifies and prompts, exactly as a tapped link does. This view knows nothing
/// about signatures.
struct ScanShareView: View {
    /// A decoded QR string (expected to be a donpa.app/s/… URL). The presenter
    /// routes it through the same `receive(_:)` path as `onOpenURL`.
    let onFound: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    #if os(macOS)
    @State private var importFailed = false
    @State private var importing = false
    @State private var dropTargeted = false
    #endif

    var body: some View {
        chrome
            #if os(macOS)
        // SwiftUI's importer (not a raw NSOpenPanel, which fails silently under
        // the App Sandbox) — presents the picker and vends a security-scoped URL.
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.png, .jpeg, .image],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
            #endif
    }

    @ViewBuilder private var content: some View {
        #if os(iOS)
        VStack(spacing: 16) {
            CameraScanner { deliver($0) }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 320)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16).strokeBorder(.secondary, lineWidth: 1))
            Text("Point the camera at a rival's QR code.", bundle: .module)
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        #elseif os(macOS)
        VStack(spacing: 16) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(dropTargeted ? Color.accentColor : .secondary)
            Text("Drag a rival's QR image here, or choose one.", bundle: .module)
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                importFailed = false
                importing = true
            } label: {
                Text("Choose image…", bundle: .module)
            }
            .buttonStyle(.borderedProminent)
            if importFailed {
                Text("No QR code found in that image.", bundle: .module)
                    .font(.caption).foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    dropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6]))
        )
        // Accept a dragged image (Finder file or an image dragged from another app).
        .dropDestination(for: Data.self) { items, _ in
            handleDrop(items)
        } isTargeted: {
            dropTargeted = $0
        }
        #endif
    }

    /// Hand a decoded string to the presenter as a URL, then dismiss. A non-URL (a
    /// random QR) is dropped — the receive flow only understands donpa.app links, and
    /// dismissing lets the user try again rather than routing a guaranteed failure.
    private func deliver(_ string: String) {
        guard let url = URL(string: string) else {
            dismiss()
            return
        }
        dismiss()
        onFound(url)
    }

    #if os(macOS)
    /// Decode the first QR in the picked image with a `CIDetector`. The URL is
    /// security-scoped (sandbox), so bracket the read with start/stop access.
    private func handleImport(_ result: Result<[URL], Error>) {
        guard let url = try? result.get().first else {
            importFailed = true  // cancelled or errored
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let image = CIImage(contentsOf: url), let string = Self.decodeQR(from: image) else {
            importFailed = true  // not a readable image / no QR found
            return
        }
        deliver(string)
    }

    /// A dropped image arrives as raw bytes (Finder file or an image from another app);
    /// decode a QR straight from the data — no security-scoped URL needed. Returns true
    /// if we consumed a droppable item.
    @discardableResult
    private func handleDrop(_ items: [Data]) -> Bool {
        importFailed = false
        guard let data = items.first, let image = CIImage(data: data),
            let string = Self.decodeQR(from: image)
        else {
            importFailed = true
            return false
        }
        deliver(string)
        return true
    }

    /// First QR string in a `CIImage`, or nil. High-accuracy detector — a screenshot
    /// of a QR can be small or skewed.
    static func decodeQR(from image: CIImage) -> String? {
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode, context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: image) ?? []
        return features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
    }
    #endif

    @ViewBuilder private var chrome: some View {
        #if os(iOS)
        NavigationStack {
            content.padding(20)
                .navigationTitle(Text("Scan QR", bundle: .module))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Cancel", bundle: .module)
                        }
                    }
                }
        }
        #else
        VStack(spacing: 16) {
            Text("Scan QR", bundle: .module).font(.title2.bold())
            content
            Button {
                dismiss()
            } label: {
                Text("Cancel", bundle: .module)
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(minWidth: 320)
        #endif
    }
}
