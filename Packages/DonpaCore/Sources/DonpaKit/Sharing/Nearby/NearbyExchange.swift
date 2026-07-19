import DonpaCore
import Foundation
import MultipeerConnectivity

/// Two-way local score exchange over MultipeerConnectivity. Both players open
/// the Nearby sheet and BOTH tap the other's name — a connection alone carries
/// nothing, cards cross only after mutual taps (see NearbyFlow, which owns the
/// handshake; this class is the MCC adapter executing its actions). Each side
/// still confirms the import through the normal receive flow.
@MainActor
final class NearbyExchange: NSObject, ObservableObject {
    typealias Phase = NearbyFlow<MCPeerID>.Phase

    @Published private(set) var phase: Phase = .browsing
    @Published private(set) var peers: [MCPeerID] = []
    /// The rival's payload link, once received — routed into the same
    /// classify/confirm path a scanned QR takes.
    @Published private(set) var receivedURL: URL?
    /// Per-direction progress for the exchanging view.
    @Published private(set) var sentOurs = false

    /// Bonjour service type (≤15 chars, lowercase/digits/hyphen).
    static let service = "donpa-swap"
    /// The tap announcement. Old builds feed received data to `URL(string:)`,
    /// which rejects spaces — so this marker is invisible to them by design.
    static let readyMarker = Data("DONPA READY 1".utf8)

    private let myPeer: MCPeerID
    private var session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser
    private let payload: Data
    private var flow = NearbyFlow<MCPeerID>()
    /// Discovery tags by peer, for the crossed-invite tie-break.
    private var peerTags: [MCPeerID: String] = [:]

    /// A short tag of the local signing key, advertised so the browser can hide the
    /// player's OWN other devices (same synchronizable identity). A prefix suffices:
    /// self-recognition, not authentication — the receive path checks the full key.
    private let selfTag: String

    init(displayName: String, payloadURL: URL, identityKey: Data?) {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        // MCPeerID rejects empty/oversized names; the share name is user text.
        myPeer = MCPeerID(displayName: trimmed.isEmpty ? "Donpa" : String(trimmed.prefix(60)))
        selfTag = (identityKey ?? Data()).prefix(9).base64EncodedString()
        session = Self.makeSession(for: myPeer)
        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeer, discoveryInfo: ["k": selfTag], serviceType: Self.service)
        browser = MCNearbyServiceBrowser(peer: myPeer, serviceType: Self.service)
        payload = Data(payloadURL.absoluteString.utf8)
        super.init()
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    private static func makeSession(for peer: MCPeerID) -> MCSession {
        MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
    }

    /// Advertise AND browse: every open sheet sees every other open sheet.
    /// Discovery runs for the sheet's whole life — retries reuse it as-is.
    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
    }

    /// The local player tapped a name — arm our side.
    func invite(_ peer: MCPeerID) {
        perform(flow.userTapped(peer))
    }

    /// The failure sheet's Retry: fresh session, same peer, warm discovery.
    func retry() {
        remakeSession()
        perform(flow.userRetried())
    }

    // MARK: Flow actions → MCC calls

    private func perform(_ actions: [NearbyFlow<MCPeerID>.Action]) {
        for action in actions {
            switch action {
            case .invite(let peer):
                // 30s over the default 20: encryption negotiation on a busy
                // radio was cutting it close.
                browser.invitePeer(
                    peer, to: session, withContext: Data(selfTag.utf8), timeout: 30)
            case .sendReady(let peer):
                send(Self.readyMarker, to: peer)
            case .sendPayload(let peer):
                if send(payload, to: peer) {
                    perform(flow.payloadSent(to: peer))
                }
            case .retry(let peer, let attempt):
                remakeSession()
                // Linear backoff, capped — enough for the radio to settle, short
                // enough that the "reconnecting" beat reads as automatic.
                let delay = Double(min(attempt, 3))
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    guard let self else { return }
                    self.perform(self.flow.retryFired(for: peer))
                }
            }
        }
        publish()
    }

    /// One failure funnel: a throwing send is the same event as a drop.
    @discardableResult
    private func send(_ data: Data, to peer: MCPeerID) -> Bool {
        do {
            try session.send(data, toPeers: [peer], with: .reliable)
            return true
        } catch {
            perform(flow.linkFailed(with: peer))
            return false
        }
    }

    /// A failed session object is not trustworthy for the next attempt —
    /// rebuild it; discovery (advertiser/browser) stays warm throughout.
    private func remakeSession() {
        session.disconnect()
        session = Self.makeSession(for: myPeer)
        session.delegate = self
    }

    private func publish() {
        phase = flow.phase
        sentOurs = flow.sentOurs
    }

    // MARK: Session plumbing (delegates arrive off-main; hop before touching state)

    private func received(_ data: Data, from peer: MCPeerID) {
        if data == Self.readyMarker {
            perform(flow.receivedReady(from: peer))
            return
        }
        guard receivedURL == nil,
            let text = String(bytes: data, encoding: .utf8),
            let url = URL(string: text)
        else { return }
        receivedURL = url
        perform(flow.receivedPayload(from: peer))
    }
}

extension NearbyExchange: MCSessionDelegate {
    nonisolated func session(
        _ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState
    ) {
        Task { @MainActor in
            switch state {
            case .connected:
                self.perform(self.flow.connected(to: peerID))
            case .notConnected:
                // The flow sorts transient drops (auto-retry) from real
                // failures; after .done it's just the other sheet closing.
                self.perform(self.flow.linkFailed(with: peerID))
            default: break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID)
    {
        Task { @MainActor in self.received(data, from: peerID) }
    }

    // Streams/resources unused — the exchange is two small Datas each way.
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
        // Accept as transport only — nothing is sent until OUR player taps.
        // Crossed invites (both tapped at once): the tie-break picks exactly
        // one hosting side; the loser's own invite wins on the mirror rule.
        Task { @MainActor in
            let theirTag =
                context.flatMap { String(bytes: $0, encoding: .utf8) }
                ?? self.peerTags[peerID] ?? ""
            let crossed: Bool
            if case .connecting(let invited) = self.flow.phase, invited == peerID {
                crossed = true
            } else {
                crossed = false
            }
            if crossed,
                !NearbyFlow<MCPeerID>.acceptsCrossedInvite(
                    myTag: self.selfTag, theirTag: theirTag)
            {
                invitationHandler(false, nil)
                return
            }
            invitationHandler(true, self.session)
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
            self.peerTags[peerID] = info?["k"] ?? ""
            if !self.peers.contains(peerID) { self.peers.append(peerID) }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in self.peers.removeAll { $0 == peerID } }
    }
}
