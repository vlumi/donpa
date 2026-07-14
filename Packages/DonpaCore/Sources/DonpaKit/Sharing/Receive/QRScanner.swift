import DonpaCore
import SwiftUI

#if os(iOS)
import AVFoundation

/// Live camera QR scanner (iOS). No frame is recorded or stored (see
/// `NSCameraUsageDescription`); the caller decides whether the string is a Donpa share.
struct CameraScanner: UIViewRepresentable {
    let onFound: (String) -> Void

    func makeUIView(context: Context) -> ScannerView {
        let view = ScannerView()
        view.onFound = onFound
        view.start()
        return view
    }

    func updateUIView(_ uiView: ScannerView, context: Context) {}

    static func dismantleUIView(_ uiView: ScannerView, coordinator: Void) {
        uiView.stop()
    }

    final class ScannerView: UIView, AVCaptureMetadataOutputObjectsDelegate {
        var onFound: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?
        /// Fire once per presentation — a QR sits in frame for many frames.
        private var handled = false

        func start() {
            guard !session.isRunning,
                let device = AVCaptureDevice.default(for: .video),
                let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input)
            else { return }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            self.layer.addSublayer(layer)
            preview = layer

            // startRunning blocks — keep capture I/O off the main thread.
            Task.detached { [session] in session.startRunning() }
        }

        func stop() {
            guard session.isRunning else { return }
            Task.detached { [session] in session.stopRunning() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            preview?.frame = bounds
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput objects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !handled,
                let code = objects.first as? AVMetadataMachineReadableCodeObject,
                let string = code.stringValue
            else { return }
            handled = true
            onFound?(string)
        }
    }
}
#endif
