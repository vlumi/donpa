import DonpaCore
import SwiftUI

/// "Share my scores" sheet: type a display name, optionally include career totals,
/// and get a QR (the primary, in-person channel — matches the trust model) plus a
/// copy/share link for remote sending. The payload is built from the MERGED
/// cross-device view; when sync is on we refresh first, and either way the footer
/// says honestly whether it's your synced best or this device only.
struct ShareScoresView: View {
    @ObservedObject var scoreboard: Scoreboard
    @ObservedObject var settings: Settings
    @Environment(\.dismiss) private var dismiss

    /// Minted lazily on first share; held for the sheet's lifetime.
    private let identityStore = ShareIdentityStore()

    @State private var name: String = ""
    @State private var includeCareer = false
    @State private var link: URL?
    @State private var qr: Image?
    @State private var failed = false

    var body: some View {
        chrome
            .onAppear {
                if name.isEmpty { name = settings.shareName }
                rebuild()
            }
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 16) {
            // Name + career opt-in drive the payload; editing rebuilds the QR/link.
            VStack(alignment: .leading, spacing: 12) {
                TextField(text: $name) {
                    Text("Your name", bundle: .module)
                }
                .textFieldStyle(.roundedBorder)
                .onChangeCompat(of: name) { _ in
                    settings.shareName = name
                    rebuild()
                }
                Toggle(isOn: $includeCareer) {
                    Text("Include career stats", bundle: .module)
                }
                .onChangeCompat(of: includeCareer) { _ in rebuild() }
            }
            .padding(.horizontal, 4)

            if let qr {
                qr
                    .interpolation(.none)  // keep QR modules crisp
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260, maxHeight: 260)
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(Text("Share QR code", bundle: .module))
            } else if failed {
                Text("Couldn't prepare your share.", bundle: .module)
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(height: 260)
            } else {
                ProgressView().frame(height: 260)
            }

            if let link {
                shareButtons(for: link)
            }

            // Honest provenance: synced best vs. this device only.
            Text(provenanceKey, bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    /// A copy-link button + the system share sheet, for sending the link remotely.
    @ViewBuilder private func shareButtons(for link: URL) -> some View {
        HStack(spacing: 12) {
            ShareLinkButton(url: link)
            #if os(iOS)
            Button {
                UIPasteboard.general.url = link
            } label: {
                Label {
                    Text("Copy link", bundle: .module)
                } icon: {
                    Image(systemName: "doc.on.doc")
                }
            }
            #elseif os(macOS)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link.absoluteString, forType: .string)
            } label: {
                Label {
                    Text("Copy link", bundle: .module)
                } icon: {
                    Image(systemName: "doc.on.doc")
                }
            }
            #endif
        }
        .buttonStyle(.bordered)
    }

    /// The footer key: synced-across-devices vs. this-device-only, mirroring how the
    /// scoreboard footer labels sync state.
    private var provenanceKey: LocalizedStringKey {
        scoreboard.isCloudActive
            ? "These are your current best scores across all your devices."
            : "Sync is off — sharing this device's current scores only."
    }

    /// Rebuild the payload → QR + link. Refresh from cloud first when sync is active
    /// so the shared blob reflects the current cross-device best.
    private func rebuild() {
        failed = false
        if scoreboard.isCloudActive { scoreboard.refreshFromCloud() }
        // The name is the sharer's own input; the RECEIVER sanitizes on decode
        // (where it matters for safety). Just trim whitespace for a tidy payload.
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let identity = identityStore.identity(),
            let payload = SharePayloadBuilder.build(
                from: scoreboard, identity: identity,
                name: trimmed.isEmpty ? "?" : trimmed, includeCareer: includeCareer, now: Date()),
            let url = try? ShareLink.url(for: payload)
        else {
            qr = nil
            link = nil
            failed = true
            return
        }
        link = url
        qr = QRCode.image(from: url.absoluteString)
    }

    /// iOS NavigationStack + Done; macOS inline + Done, matching the other sheets.
    @ViewBuilder private var chrome: some View {
        #if os(iOS)
        NavigationStack {
            ScrollView { content.padding(20) }
                .navigationTitle(Text("Share scores", bundle: .module))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Done", bundle: .module)
                        }
                    }
                }
        }
        #else
        VStack(spacing: 16) {
            Text("Share scores", bundle: .module).font(.title2.bold())
            content
            Button {
                dismiss()
            } label: {
                Text("Done", bundle: .module)
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(minWidth: 340)
        #endif
    }
}

/// A thin wrapper over SwiftUI's `ShareLink` (the system share sheet) so the call
/// site stays clean and cross-platform.
private struct ShareLinkButton: View {
    let url: URL
    var body: some View {
        ShareLink(item: url) {
            Label {
                Text("Send link", bundle: .module)
            } icon: {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }
}
