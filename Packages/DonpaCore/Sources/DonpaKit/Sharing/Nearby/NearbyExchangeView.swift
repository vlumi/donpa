import DonpaCore
import MultipeerConnectivity
import SwiftUI

/// The Nearby sheet; the received card goes to the host's normal receive/confirm
/// flow, same as a scanned QR.
struct NearbyExchangeView: View {
    @StateObject private var exchange: NearbyExchange
    let onReceived: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    /// Tracked by IDENTITY, not list position: peers appear and drop mid-browse,
    /// and an index could silently retarget Return's invite at someone else.
    @State private var focusedPeer: MCPeerID?

    init(
        displayName: String, payloadURL: URL, identityKey: Data?,
        onReceived: @escaping (URL) -> Void
    ) {
        _exchange = StateObject(
            wrappedValue: NearbyExchange(
                displayName: displayName, payloadURL: payloadURL, identityKey: identityKey))
        self.onReceived = onReceived
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            ViewThatFits(in: .vertical) {
                phaseContent
                ScrollView { phaseContent }
            }
            Spacer(minLength: 0)
            dismissButton
        }
        .padding(20)
        .frame(minWidth: 300, idealWidth: 340, minHeight: 360)
        .escDismisses(close)
        .background(nearbyKeyCatcher)
        .onAppear { exchange.start() }
        .onDisappear { exchange.stop() }
    }

    @ViewBuilder private var phaseContent: some View {
        switch exchange.phase {
        case .browsing:
            browsing
        case .connecting(let peer):
            status(Text("Connecting to \(peer.displayName)…", bundle: .module), spinner: true)
        case .waitingForTap(let peer):
            status(
                Text("Waiting for \(peer.displayName) to tap your name…", bundle: .module),
                spinner: true)
        case .exchanging(let peer):
            exchanging(peer.displayName)
        case .reconnecting(let peer):
            status(
                Text("Connection hiccup — retrying with \(peer.displayName)…", bundle: .module),
                spinner: true)
        case .done(let peer):
            done(peer.displayName)
        case .failed(let peer):
            failed(peer)
        }
    }

    /// Both sides tapped; show each direction's own progress.
    private func exchanging(_ name: String) -> some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Swapping scores with \(name)…", bundle: .module)
                .font(.callout).foregroundStyle(.secondary)
            directionTick(
                done: exchange.sentOurs,
                doneText: Text("Your card is sent.", bundle: .module),
                pendingText: Text("Sending your card…", bundle: .module))
            directionTick(
                done: exchange.receivedURL != nil,
                doneText: Text("Their card arrived.", bundle: .module),
                pendingText: Text("Waiting for their card…", bundle: .module))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func directionTick(done: Bool, doneText: Text, pendingText: Text) -> some View {
        Label {
            (done ? doneText : pendingText).font(.caption)
        } icon: {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dotted")
                .foregroundStyle(done ? .green : .secondary)
        }
        .foregroundStyle(.secondary)
    }

    /// The automatic retries are spent — offer a manual one. Discovery stayed
    /// warm, so Retry re-invites the same player directly.
    private func failed(_ peer: MCPeerID?) -> some View {
        VStack(spacing: 10) {
            status(Text("The connection dropped.", bundle: .module), spinner: false)
            if peer != nil {
                Button {
                    exchange.retry()
                } label: {
                    Text("Try again", bundle: .module).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    /// Every close path routes an already-received card into the confirm flow —
    /// dismissing must never drop it, or the whole handshake has to be redone.
    private func close() {
        let received = exchange.receivedURL
        dismiss()
        if let received { onReceived(received) }
    }

    /// Arrows pick a nearby player, Return taps them — or retries a failed
    /// swap, or, once cards have crossed, adds the received one.
    @ViewBuilder private var nearbyKeyCatcher: some View {
        #if os(macOS)
        KeyCatcher { key in
            switch key {
            case .down, .tab: movePeerFocus(1)
            case .up, .backTab: movePeerFocus(-1)
            case .enter, .space: activate()
            case .escape: close()
            case .click: focusedPeer = nil  // mouse takes over
            default: break
            }
        }
        #endif
    }

    #if os(macOS)
    private func movePeerFocus(_ delta: Int) {
        guard case .browsing = exchange.phase, !exchange.peers.isEmpty else { return }
        guard let current = focusedPeer, let i = exchange.peers.firstIndex(of: current) else {
            focusedPeer = exchange.peers.first
            return
        }
        focusedPeer = exchange.peers[min(max(i + delta, 0), exchange.peers.count - 1)]
    }

    private func activate() {
        switch exchange.phase {
        case .browsing:
            guard let peer = focusedPeer, exchange.peers.contains(peer) else { return }
            exchange.invite(peer)
        case .failed(let peer):
            if peer != nil { exchange.retry() }
        case .done:
            guard let url = exchange.receivedURL else { return }
            dismiss()
            onReceived(url)
        default:
            break
        }
    }
    #endif

    /// Once a card has arrived, closing routes it into the confirm flow (same as
    /// "Add their card"); otherwise it's a plain cancel.
    @ViewBuilder private var dismissButton: some View {
        if let url = exchange.receivedURL {
            Button {
                dismiss()
                onReceived(url)
            } label: {
                Text("Close", bundle: .module).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        } else {
            Button {
                dismiss()
            } label: {
                Text("Cancel", bundle: .module).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.line.dotted.person.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
            Text("Nearby exchange", bundle: .module).font(.headline)
            Text(
                """
                Open this on both devices, then each tap the other's name. \
                Cards cross both ways only after both taps — nothing leaves \
                the room.
                """, bundle: .module
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
    }

    private var browsing: some View {
        VStack(spacing: 10) {
            if exchange.peers.isEmpty {
                status(Text("Looking for nearby players…", bundle: .module), spinner: true)
            } else {
                ForEach(exchange.peers, id: \.self) { peer in
                    Button {
                        exchange.invite(peer)
                    } label: {
                        Label {
                            Text(verbatim: peer.displayName)
                        } icon: {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyFocusRing(focusedPeer == peer)
                }
            }
        }
    }

    private func done(_ name: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title)
                .foregroundStyle(.green)
            Text("Cards swapped with \(name).", bundle: .module)
                .font(.callout.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("They got yours — now add theirs.", bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
            Button {
                guard let url = exchange.receivedURL else { return }
                dismiss()
                onReceived(url)
            } label: {
                Text("Add their card", bundle: .module).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(exchange.receivedURL == nil)
        }
    }

    private func status(_ text: Text, spinner: Bool) -> some View {
        VStack(spacing: 8) {
            if spinner { ProgressView() }
            text.font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
