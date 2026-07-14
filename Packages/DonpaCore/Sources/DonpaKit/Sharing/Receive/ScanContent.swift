import CoreImage
import DonpaCore
import SwiftUI

#if os(macOS)
import UniformTypeIdentifiers
#endif

/// The QR-scanning surface: iOS scans live with the camera; macOS imports/drops an
/// image. Knows nothing about signatures — the receive flow verifies and prompts.
struct ScanContent: View {
    let onFound: (URL) -> Void

    #if os(macOS)
    @State private var importFailed = false
    @State private var importing = false
    @State private var dropTargeted = false
    #endif

    var body: some View {
        inner
            #if os(macOS)
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.png, .jpeg, .image],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
            #endif
    }

    @ViewBuilder private var inner: some View {
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
        .dropDestination(for: Data.self) { items, _ in
            handleDrop(items)
        } isTargeted: {
            dropTargeted = $0
        }
        #endif
    }

    private func deliver(_ string: String) {
        guard let url = URL(string: string) else { return }
        onFound(url)
    }

    #if os(macOS)
    /// The picked URL is security-scoped (sandbox) — bracket the read with start/stop.
    private func handleImport(_ result: Result<[URL], Error>) {
        guard let url = try? result.get().first else {
            importFailed = true
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let image = CIImage(contentsOf: url), let string = Self.decodeQR(from: image) else {
            importFailed = true
            return
        }
        deliver(string)
    }

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

    /// High-accuracy detector — a screenshot of a QR can be small or skewed.
    static func decodeQR(from image: CIImage) -> String? {
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode, context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: image) ?? []
        return features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
    }
    #endif
}
