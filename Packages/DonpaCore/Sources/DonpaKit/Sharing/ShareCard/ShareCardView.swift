import DonpaCore
import SwiftUI
import UniformTypeIdentifiers

/// The inline "share my scores" card — lives ON the Mess hall, not behind a
/// sheet: your name, career opt-in, and the sharing actions, kept deliberately
/// LEAN (every row here starves the rivals list below). **Nearby is the
/// promoted default**; link and the QR (behind a button, full-size on demand
/// with the image exports) are the remote row. The payload is built from the
/// MERGED cross-device view; when sync is on we refresh first.
struct ShareCardView: View {
    @ObservedObject var scoreboard: Scoreboard
    @ObservedObject var settings: Settings
    @ObservedObject var dailyStore: DailyStore
    /// Open the Nearby exchange — the promoted, in-person path. The host owns the
    /// sheet (it also receives the swapped card); the card owns the gate: the
    /// button only shows once a name has produced a shareable link.
    var onNearby: (() -> Void)?
    /// The card control the host's Tab-cycling has focused (ring + activation
    /// target), or nil.
    var keyFocus: KeyFocus?
    /// Fired by the host to activate the focused control from the keyboard.
    var activate = Pulse()
    /// Reports whether a link is currently built — the host's keyboard zones
    /// follow it (no reachable zones for buttons that aren't rendered).
    var hasLink: Binding<Bool>?

    /// The card's keyboard-focusable controls, in visual order.
    enum KeyFocus { case name, career, nearby, shareLink, qr }

    /// Minted lazily on first share; held for the card's lifetime.
    private let identityStore = ShareIdentityStore()

    /// The QR/link path carries a rolling daily window (scan budget); Nearby
    /// sends the full history — receivers accumulate per date either way.
    static let qrDailyWindow = 14

    #if os(iOS)
    /// Compact width (iPhone) stacks the share buttons; regular (iPad) rows them.
    @Environment(\.horizontalSizeClass) private var hSizeClass
    #endif

    @State private var name: String = ""
    @State private var link: URL?
    @State private var qr: Image?
    @State private var failed = false
    /// The full-size QR sheet (behind the "QR code" button).
    @State private var enlarged = false
    /// Keyboard focus for the name field (the host's Return on the name zone).
    @FocusState private var nameFocused: Bool
    /// Fired to open the macOS share picker from the keyboard (ShareLink
    /// itself can't be invoked programmatically).
    @State private var sharePick = Pulse()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Name + career toggle share a row where width allows (the field
            // keeps a usable minimum); narrow portrait phones stack them.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    nameField.frame(minWidth: 140)
                    careerToggle.fixedSize()
                }
                VStack(alignment: .leading, spacing: 8) {
                    nameField
                    careerToggle
                }
            }
            if let link {
                shareActions(for: link)
            } else if trimmedName.isEmpty {
                // A nameless card would go out stamped "?" — a poor first
                // handshake in a name-is-identity model. Nudge, don't ship it.
                Text("Add your name to share.", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
            } else if failed {
                Text("Couldn't prepare your share.", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.primary.opacity(0.05))
        )
        .appearanceSheet(isPresented: $enlarged, settings) {
            QRZoomSheet(qr: qr, name: trimmedName, link: link)
        }
        .onAppear {
            // Pull the latest synced name (iCloud Keychain has no change
            // notifications, so opening the card is the refresh point) BEFORE
            // seeding the field from it.
            settings.reconcileShareName()
            if name.isEmpty { name = settings.shareName }
            rebuild()
        }
        .onPulse(activate) { activateFocusedControl() }
    }

    /// The host's keyboard activation, routed to whichever control its
    /// Tab-cycling has focused.
    private func activateFocusedControl() {
        switch keyFocus {
        case .name: nameFocused = true
        case .career: settings.shareIncludeCareer.toggle()
        case .nearby: onNearby?()
        case .shareLink: sharePick.fire()
        case .qr: enlarged = true
        case nil: break
        }
    }

    private func ring(_ control: KeyFocus) -> FocusRing {
        FocusRing(focused: keyFocus == control, inset: 2)
    }

    private var nameField: some View {
        TextField(text: $name) {
            Text("Your name", bundle: .module)
        }
        .textFieldStyle(.roundedBorder)
        .focused($nameFocused)
        .modifier(ring(.name))
        .onChangeCompat(of: name) { _ in
            settings.shareName = name
            rebuild()
        }
    }

    private var careerToggle: some View {
        Toggle(isOn: $settings.shareIncludeCareer) {
            Text("Include career stats", bundle: .module)
                // Wrap on a narrow column instead of truncating to
                // "Include care…".
                .fixedSize(horizontal: false, vertical: true)
        }
        .modifier(ring(.career))
        .onChangeCompat(of: settings.shareIncludeCareer) { _ in rebuild() }
    }

    /// All the share actions. On a WIDE canvas (iPad, Mac) they sit in one row —
    /// Nearby (the promoted default) beside the remote pair. On a phone the three
    /// labels can't share a row without truncating ("Sh…", "QR…"), so Nearby
    /// takes the top row and the remote pair stacks below it. Decided by size
    /// class rather than ViewThatFits, which counts truncated text as "fitting".
    @ViewBuilder private func shareActions(for link: URL) -> some View {
        if onNearby != nil {
            if isWideLayout {
                HStack(spacing: 8) {
                    nearbyButton
                    remoteButtons(for: link).frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 8) {
                    nearbyButton
                    remoteButtons(for: link)
                }
            }
        } else {
            remoteButtons(for: link)
        }
    }

    /// One row only where there's genuinely room: iPad (regular width) and Mac.
    private var isWideLayout: Bool {
        #if os(macOS)
        return true
        #else
        return hSizeClass == .regular
        #endif
    }

    @ViewBuilder private var nearbyButton: some View {
        if let onNearby {
            Button(action: onNearby) {
                Label {
                    Text("Nearby", bundle: .module)
                } icon: {
                    // Not person.line.dotted.person.fill: it renders on macOS
                    // but comes up empty on iOS.
                    Image(systemName: "person.2.wave.2.fill")
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .modifier(ring(.nearby))
        }
    }

    /// The remote channels: send the link (the system share sheet already offers
    /// Copy, so no separate copy button) and show the QR full size — the
    /// branded-card image exports (share/save) live inside the QR view, beside
    /// the code they render.
    private func remoteButtons(for link: URL) -> some View {
        HStack(spacing: 8) {
            #if os(macOS)
            SharePickerButton(url: link, activate: sharePick)
                .modifier(ring(.shareLink))
            #else
            ShareLinkButton(url: link)
            #endif
            if qr != nil {
                Button {
                    enlarged = true
                } label: {
                    Label {
                        Text("QR code", bundle: .module)
                    } icon: {
                        Image(systemName: "qrcode")
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                }
                .modifier(ring(.qr))
                .accessibilityHint(Text("Shows the code full size.", bundle: .module))
            }
        }
        .buttonStyle(.bordered)
    }

    /// The trimmed name: stamped on the card, and (when empty) the sharing
    /// gate — see the nudge above for the why.
    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Rebuild the payload → QR + link, through the ONE shared gate chain
    /// (SharePayloadBuilder.currentURL — Nearby and the keyboard zones read
    /// the same one). `settings.shareName` is kept in sync by the field's
    /// onChange, so the builder's copy is this field's text.
    private func rebuild() {
        failed = false
        defer { hasLink?.wrappedValue = link != nil }
        // No name → no card. The QR/buttons stay hidden and the field shows a nudge.
        guard !trimmedName.isEmpty else {
            qr = nil
            link = nil
            return
        }
        guard
            let url = SharePayloadBuilder.currentURL(
                scoreboard: scoreboard, settings: settings, identityStore: identityStore,
                dailyStore: dailyStore, dailyDays: Self.qrDailyWindow)
        else {
            qr = nil
            link = nil
            failed = true
            return
        }
        link = url
        // The QR gets its own budgeted URL (ShareQRBudget) — an oversized
        // card overflows the encoder; the link above keeps the full payload.
        qr = SharePayloadBuilder.qrURL(
            scoreboard: scoreboard, settings: settings, identityStore: identityStore,
            dailyStore: dailyStore
        ).flatMap { QRCode.image(from: $0.absoluteString) }
    }

}
