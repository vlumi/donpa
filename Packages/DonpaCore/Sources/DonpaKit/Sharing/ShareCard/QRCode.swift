import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum QRCode {
    /// Separate from `image` so the round-trip test can decode the exact bytes rendered.
    static func ciImage(from string: String, scale: CGFloat = 10) -> CIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        // Medium: some robustness without inflating an already-long share URL's module count.
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

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
