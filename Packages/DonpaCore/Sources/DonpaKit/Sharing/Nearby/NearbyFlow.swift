import Foundation

/// The Nearby exchange's handshake brain — pure state, no MultipeerConnectivity,
/// so the whole protocol is unit-testable headless. `NearbyExchange` feeds it
/// events and executes the actions it returns.
///
/// The protocol (see ARCHITECTURE.md "Nearby exchange"): a connection is just
/// transport — nothing is sent on it until BOTH players have tapped each other.
/// A tap arms your side and announces it with a tiny READY marker; your card
/// leaves your device only once you're armed AND theirs has arrived (their
/// READY, or their card itself — an older build's card implies consent, it
/// sent one only because its user tapped).
struct NearbyFlow<Peer: Hashable> {
    /// What the adapter must do after an event. Order matters.
    enum Action: Equatable {
        case invite(Peer)
        case sendReady(Peer)
        case sendPayload(Peer)
        /// Tear down and rebuild the session, then re-invite after a beat —
        /// the automatic retry. `attempt` drives the backoff.
        case retry(Peer, attempt: Int)
    }

    /// What the sheet renders. Failure keeps the peer so Retry can re-target.
    enum Phase: Equatable {
        case browsing
        case connecting(Peer)
        /// Connected and armed; their tap hasn't landed yet.
        case waitingForTap(Peer)
        case exchanging(Peer)
        case reconnecting(Peer)
        case done(Peer)
        case failed(Peer?)
    }

    /// Automatic retries after a drop/send failure, before failing loudly.
    static var maxAutoRetries: Int { 2 }

    private(set) var phase: Phase = .browsing
    /// The peer the local player tapped — the ONLY peer we'll ever send to.
    private(set) var armedPeer: Peer?
    private(set) var sentOurs = false
    private(set) var gotTheirs = false
    private var connected: Set<Peer> = []
    private var remoteReady: Set<Peer> = []
    private var attempts = 0

    // MARK: Events

    /// The local tap — arms this side. Invites when no transport exists yet;
    /// announces readiness right away when it does.
    mutating func userTapped(_ peer: Peer) -> [Action] {
        guard armedPeer == nil, !isSettled else { return [] }
        armedPeer = peer
        if connected.contains(peer) {
            phase = remoteReady.contains(peer) ? .exchanging(peer) : .waitingForTap(peer)
            return [.sendReady(peer)] + payloadIfBothReady(peer)
        }
        phase = .connecting(peer)
        return [.invite(peer)]
    }

    /// The failure sheet's Retry — same target, fresh automatic budget.
    mutating func userRetried() -> [Action] {
        guard case .failed(let peer?) = phase else { return [] }
        attempts = 0
        connected.remove(peer)
        remoteReady.remove(peer)
        sentOurs = false
        phase = .connecting(peer)
        return [.invite(peer)]
    }

    mutating func connected(to peer: Peer) -> [Action] {
        connected.insert(peer)
        guard armedPeer == peer else { return [] }
        phase = gotTheirs || remoteReady.contains(peer) ? .exchanging(peer) : .waitingForTap(peer)
        return [.sendReady(peer)] + payloadIfBothReady(peer)
    }

    mutating func receivedReady(from peer: Peer) -> [Action] {
        remoteReady.insert(peer)
        guard armedPeer == peer else { return [] }
        if case .waitingForTap = phase { phase = .exchanging(peer) }
        return payloadIfBothReady(peer)
    }

    /// Their card arrived. An old build sends it straight on connect — treat it
    /// as their READY too, but ours still waits for OUR tap.
    mutating func receivedPayload(from peer: Peer) -> [Action] {
        gotTheirs = true
        remoteReady.insert(peer)
        let actions = armedPeer == peer ? payloadIfBothReady(peer) : []
        settleIfDone(with: peer)
        return actions
    }

    mutating func payloadSent(to peer: Peer) -> [Action] {
        sentOurs = true
        settleIfDone(with: peer)
        return []
    }

    /// A drop or a failed send. Transparent retries first; loud failure after.
    /// Idempotent while a retry is pending — a dying session can report the
    /// same collapse through several callbacks.
    mutating func linkFailed(with peer: Peer) -> [Action] {
        connected.remove(peer)
        remoteReady.remove(peer)
        guard armedPeer == peer, !isSettled else { return [] }
        if case .reconnecting = phase { return [] }
        // A retried exchange restarts the handshake — both directions resend
        // (the receiver dedupes, so a duplicate card is harmless).
        sentOurs = false
        guard attempts < Self.maxAutoRetries else {
            phase = .failed(peer)
            return []
        }
        attempts += 1
        phase = .reconnecting(peer)
        return [.retry(peer, attempt: attempts)]
    }

    /// The scheduled retry firing (the adapter has rebuilt the session).
    /// Phase returns to `.connecting` so the NEXT collapse counts against the
    /// budget — `.reconnecting` only absorbs the duplicate callbacks of one.
    mutating func retryFired(for peer: Peer) -> [Action] {
        guard armedPeer == peer, case .reconnecting = phase else { return [] }
        phase = .connecting(peer)
        return [.invite(peer)]
    }

    /// Crossed invites (both tapped at once): exactly one side accepts, by a
    /// comparison both sides can compute. Lower tag hosts; equal tags (no
    /// identity minted yet) fall back to accepting, which at worst recreates
    /// today's race instead of deadlocking.
    static func acceptsCrossedInvite(myTag: String, theirTag: String) -> Bool {
        theirTag <= myTag
    }

    // MARK: Plumbing

    private var isSettled: Bool {
        if case .done = phase { return true }
        return false
    }

    private mutating func payloadIfBothReady(_ peer: Peer) -> [Action] {
        guard armedPeer == peer, connected.contains(peer), remoteReady.contains(peer),
            !sentOurs
        else { return [] }
        return [.sendPayload(peer)]
    }

    private mutating func settleIfDone(with peer: Peer) {
        if sentOurs, gotTheirs { phase = .done(peer) }
    }
}
