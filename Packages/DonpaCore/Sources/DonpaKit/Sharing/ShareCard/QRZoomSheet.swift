import DonpaCore
import SwiftUI

/// The QR at scanning size, with the branded-card image exports beside it.
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
        // Low floors so small scaled displays can shrink it; capped at the ideal
        // because macOS won't resize a sheet's width, so extra height is dead space.
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
                    // macOS's share picker has no save-to-disk service, unlike iOS's sheet.
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

    /// Arrows/Tab move between the export buttons; Return with none focused is Done.
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
            case .click: keyIndex = nil  // mouse takes over
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

    private func moveFocus(_ delta: Int) {
        guard qr != nil, link != nil else { return }
        keyIndex = KeyStep.moved(keyIndex, by: delta, count: 2)
    }
    #endif
}
