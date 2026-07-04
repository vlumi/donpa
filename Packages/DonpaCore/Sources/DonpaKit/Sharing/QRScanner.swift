import DonpaCore
import SwiftUI

#if os(iOS)
import AVFoundation

/// A live camera QR scanner (iOS). Wraps an `AVCaptureSession` in a UIView and
/// reports the first machine-readable string it sees; the caller decides whether
/// it's a Donpa share. The session is discarded when the view goes away — no frame
/// is recorded or stored (see `NSCameraUsageDescription`).
struct CameraScanner: UIViewRepresentable {
    /// Called on the main actor with each decoded payload string. The caller
    /// debounces / dismisses; we keep firing until torn down.
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

    /// The backing view: owns the capture session + preview layer and forwards
    /// decoded metadata objects. A plain UIView (not the SwiftUI layer) so the
    /// preview layer resizes with `layoutSubviews`.
    final class ScannerView: UIView, AVCaptureMetadataOutputObjectsDelegate {
        var onFound: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?
        /// Fire once per presentation — a QR sits in frame for many frames, and we
        /// don't want to re-route the same link dozens of times.
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

            // Capture I/O off the main thread; the delegate still hops back to main.
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
