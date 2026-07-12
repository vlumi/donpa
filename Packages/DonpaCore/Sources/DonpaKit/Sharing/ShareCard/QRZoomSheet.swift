import DonpaCore
import SwiftUI

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
    @State private var sharePulse = Pulse()
    @State private var savePulse = Pulse()

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
                    ShareImageButton(qr: qr, name: name, linkID: link, activate: sharePulse)
                        .keyFocusRing(keyIndex == 0)
                    #if os(macOS)
                    // macOS's share picker has NO save-to-disk service (iOS's
                    // sheet offers "Save to Files"), so saving the card is its
                    // own button + save panel.
                    SaveImageButton(qr: qr, name: name, linkID: link, activate: savePulse)
                        .keyFocusRing(keyIndex == 1)
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
        if keyIndex == 0 { sharePulse.fire() }
        if keyIndex == 1 { savePulse.fire() }
    }
    #endif

    #if os(macOS)
    private func moveFocus(_ delta: Int) {
        guard qr != nil, link != nil else { return }
        keyIndex = KeyStep.moved(keyIndex, by: delta, count: 2)
    }
    #endif
}
