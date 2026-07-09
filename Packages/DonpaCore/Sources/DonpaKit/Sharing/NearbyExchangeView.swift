import DonpaCore
import SwiftUI

/// The Nearby sheet: open it on both devices, tap the other player's name,
/// and the two share cards cross in one handshake. The received card is
/// handed to the host's normal receive/confirm flow (same as a scanned QR).
struct NearbyExchangeView: View {
    @StateObject private var exchange: NearbyExchange
    /// Route the rival's received link into the root classify/confirm path.
    let onReceived: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    init(displayName: String, payloadURL: URL, onReceived: @escaping (URL) -> Void) {
        _exchange = StateObject(
            wrappedValue: NearbyExchange(displayName: displayName, payloadURL: payloadURL))
        self.onReceived = onReceived
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            switch exchange.phase {
            case .browsing:
                browsing
            case .connecting(let name):
                status(Text("Connecting to \(name)…", bundle: .module), spinner: true)
            case .exchanging(let name):
                status(Text("Swapping scores with \(name)…", bundle: .module), spinner: true)
            case .done(let name):
                done(name)
            case .failed:
                status(Text("The connection dropped — try again.", bundle: .module), spinner: false)
            }
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Text("Cancel", bundle: .module).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .frame(minWidth: 300, idealWidth: 340, minHeight: 360)
        .onAppear { exchange.start() }
        .onDisappear { exchange.stop() }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.line.dotted.person.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
            Text("Nearby exchange", bundle: .module).font(.headline)
            Text(
                """
                Open this on both devices, then tap the other player. You \
                swap score cards both ways in one go — nothing leaves the room.
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
