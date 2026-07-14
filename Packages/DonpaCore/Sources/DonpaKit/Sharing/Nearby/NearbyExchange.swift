import DonpaCore
import Foundation
import MultipeerConnectivity

/// Two-way local score exchange over MultipeerConnectivity: both players open the
/// Nearby sheet, one taps the other's name, and BOTH share payloads cross in a
/// single handshake. Each side still confirms the import through the normal
/// receive flow.
@MainActor
final class NearbyExchange: NSObject, ObservableObject {
    enum Phase: Equatable {
        case browsing
        case connecting(String)
        case exchanging(String)
        /// Both directions done: ours sent, theirs received (URL handed out).
        case done(String)
        case failed
    }

    @Published private(set) var phase: Phase = .browsing
    @Published private(set) var peers: [MCPeerID] = []
    /// The rival's payload link, once received — routed into the same
    /// classify/confirm path a scanned QR takes.
    @Published private(set) var receivedURL: URL?

    /// Bonjour service type (≤15 chars, lowercase/digits/hyphen).
    static let service = "donpa-swap"

    private let myPeer: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser
    private let payload: Data
    private var sent = false

    /// A short tag of the local signing key, advertised so the browser can hide the
    /// player's OWN other devices (same synchronizable identity). A prefix suffices:
    /// self-recognition, not authentication — the receive path checks the full key.
    private let selfTag: String

    init(displayName: String, payloadURL: URL, identityKey: Data?) {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        // MCPeerID rejects empty/oversized names; the share name is user text.
        myPeer = MCPeerID(displayName: trimmed.isEmpty ? "Donpa" : String(trimmed.prefix(60)))
        selfTag = (identityKey ?? Data()).prefix(9).base64EncodedString()
        session = MCSession(
            peer: myPeer, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeer, discoveryInfo: ["k": selfTag], serviceType: Self.service)
        browser = MCNearbyServiceBrowser(peer: myPeer, serviceType: Self.service)
        payload = Data(payloadURL.absoluteString.utf8)
        super.init()
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    /// Advertise AND browse: every open sheet sees every other open sheet, and
    /// whoever taps first becomes the inviter (the other side auto-accepts).
    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
    }

    func invite(_ peer: MCPeerID) {
        phase = .connecting(peer.displayName)
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 20)
    }

    // MARK: Session plumbing (delegates arrive off-main; hop before touching state)

    private func connected(to peer: MCPeerID) {
        phase = .exchanging(peer.displayName)
        guard !sent else { return }
        sent = true
        try? session.send(payload, toPeers: [peer], with: .reliable)
        settle(with: peer)
    }

    private func received(_ data: Data, from peer: MCPeerID) {
        guard receivedURL == nil,
            let text = String(bytes: data, encoding: .utf8),
            let url = URL(string: text)
        else { return }
        receivedURL = url
        settle(with: peer)
    }

    private func settle(with peer: MCPeerID) {
        if sent, receivedURL != nil { phase = .done(peer.displayName) }
    }
}

extension NearbyExchange: MCSessionDelegate {
    nonisolated func session(
        _ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState
    ) {
        Task { @MainActor in
            switch state {
            case .connected: self.connected(to: peerID)
            case .notConnected:
                // A drop before both directions completed is a failure; after .done,
                // it's just the other side closing their sheet.
                if case .done = self.phase { return }
                if case .browsing = self.phase { return }
                self.phase = .failed
            default: break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID)
    {
        Task { @MainActor in self.received(data, from: peerID) }
    }

    // Streams/resources unused — the exchange is one small Data each way.
    nonisolated func session(
        _ session: MCSession, didReceive stream: InputStream, withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}
    nonisolated func session(
        _ session: MCSession, didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID, with progress: Progress
    ) {}
    nonisolated func session(
        _ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?
    ) {}
}

extension NearbyExchange: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        // Auto-accept: opening the sheet IS the consent gesture (the import
        // still runs through the normal confirm sheet).
        Task { @MainActor in
            invitationHandler(true, self.session)
            self.phase = .connecting(peerID.displayName)
        }
    }
}

extension NearbyExchange: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        Task { @MainActor in
            guard info?["k"] != self.selfTag else { return }
            if !self.peers.contains(peerID) { self.peers.append(peerID) }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in self.peers.removeAll { $0 == peerID } }
    }
}
