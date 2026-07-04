import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Renders a string (the share Universal Link) as a QR code `Image`. CoreImage's
/// generator produces a tiny bitmap; we upscale nearest-neighbour so the modules
/// stay crisp at display size. Pure presentation — no app state.
enum QRCode {
    /// The raw upscaled `CIImage` of `string` as a QR, or nil if generation fails.
    /// `scale` multiplies the raw module bitmap (10 keeps a dense share URL sharp).
    /// Split out so the QR round-trip test can decode the exact bytes we render.
    static func ciImage(from string: String, scale: CGFloat = 10) -> CIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        // Medium error correction: some robustness without inflating the module
        // count of an already-long share URL.
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    /// A crisp SwiftUI `Image` of `string` as a QR, or nil if generation fails.
    static func image(from string: String, scale: CGFloat = 10) -> Image? {
        guard let scaled = ciImage(from: string, scale: scale),
            let cg = CIContext().createCGImage(scaled, from: scaled.extent)
        else { return nil }

        #if os(iOS)
        return Image(uiImage: UIImage(cgImage: cg))
        #elseif os(macOS)
        return Image(nsImage: NSImage(cgImage: cg, size: .zero))
        #endif
    }
}
