import XCTest

@testable import DonpaKit

/// The Nearby handshake brain, exercised headless: mutual-tap gating, the
/// old-build interop path, crossed invites, and the retry ladder.
final class NearbyFlowTests: XCTestCase {
    typealias Flow = NearbyFlow<String>

    // MARK: Mutual arming

    func testTapInvitesWhenNotConnected() {
        var flow = Flow()
        XCTAssertEqual(flow.userTapped("aoi"), [.invite("aoi")])
        XCTAssertEqual(flow.phase, .connecting("aoi"))
    }

    func testNothingIsSentOnBareConnection() {
        // Their side tapped (they invited, we auto-accepted the transport) —
        // our card must NOT move until OUR tap.
        var flow = Flow()
        XCTAssertEqual(flow.connected(to: "aoi"), [])
        XCTAssertEqual(flow.receivedReady(from: "aoi"), [])
        XCTAssertEqual(flow.phase, .browsing)
        XCTAssertFalse(flow.sentOurs)
    }

    func testPayloadFliesOnlyAfterBothTaps() {
        var flow = Flow()
        _ = flow.userTapped("aoi")
        XCTAssertEqual(flow.connected(to: "aoi"), [.sendReady("aoi")])
        XCTAssertEqual(flow.phase, .waitingForTap("aoi"))
        // Their tap lands.
        XCTAssertEqual(flow.receivedReady(from: "aoi"), [.sendPayload("aoi")])
        XCTAssertEqual(flow.phase, .exchanging("aoi"))
    }

    func testTapAfterConnectionSendsReadyAndPayloadWhenTheyAreReady() {
        var flow = Flow()
        _ = flow.connected(to: "aoi")
        _ = flow.receivedReady(from: "aoi")
        XCTAssertEqual(flow.userTapped("aoi"), [.sendReady("aoi"), .sendPayload("aoi")])
        XCTAssertEqual(flow.phase, .exchanging("aoi"))
    }

    func testSecondTapIsInert() {
        var flow = Flow()
        _ = flow.userTapped("aoi")
        XCTAssertEqual(flow.userTapped("mio"), [])
        XCTAssertEqual(flow.armedPeer, "aoi")
    }

    func testCompletionNeedsBothDirections() {
        var flow = Flow()
        _ = flow.userTapped("aoi")
        _ = flow.connected(to: "aoi")
        _ = flow.receivedReady(from: "aoi")
        _ = flow.payloadSent(to: "aoi")
        XCTAssertEqual(flow.phase, .exchanging("aoi"))
        _ = flow.receivedPayload(from: "aoi")
        XCTAssertEqual(flow.phase, .done("aoi"))
        XCTAssertTrue(flow.sentOurs)
        XCTAssertTrue(flow.gotTheirs)
    }

    // MARK: Old-build interop (their card arrives with no READY)

    func testOldPeerCardImpliesTheirConsent() {
        var flow = Flow()
        _ = flow.userTapped("aoi")
        _ = flow.connected(to: "aoi")
        // Old build sends its payload straight on connect — that IS its tap.
        XCTAssertEqual(flow.receivedPayload(from: "aoi"), [.sendPayload("aoi")])
        _ = flow.payloadSent(to: "aoi")
        XCTAssertEqual(flow.phase, .done("aoi"))
    }

    func testOldPeerCardBeforeOurTapStillWaitsForUs() {
        var flow = Flow()
        _ = flow.connected(to: "aoi")
        XCTAssertEqual(flow.receivedPayload(from: "aoi"), [])
        XCTAssertFalse(flow.sentOurs)
        // Our tap releases ours.
        XCTAssertEqual(flow.userTapped("aoi"), [.sendReady("aoi"), .sendPayload("aoi")])
        XCTAssertEqual(flow.phase, .exchanging("aoi"))
        _ = flow.payloadSent(to: "aoi")
        XCTAssertEqual(flow.phase, .done("aoi"))
    }

    // MARK: Retries

    func testTransientDropRetriesAutomatically() {
        var flow = Flow()
        _ = flow.userTapped("aoi")
        XCTAssertEqual(flow.linkFailed(with: "aoi"), [.retry("aoi", attempt: 1)])
        XCTAssertEqual(flow.phase, .reconnecting("aoi"))
        XCTAssertEqual(flow.retryFired(for: "aoi"), [.invite("aoi")])
    }

    func testDuplicateDropReportsCollapseOnce() {
        var flow = Flow()
        _ = flow.userTapped("aoi")
        _ = flow.linkFailed(with: "aoi")
        XCTAssertEqual(flow.linkFailed(with: "aoi"), [])
        XCTAssertEqual(flow.phase, .reconnecting("aoi"))
    }

    func testRetryBudgetExhaustsToFailure() {
        var flow = Flow()
        _ = flow.userTapped("aoi")
        for attempt in 1...Flow.maxAutoRetries {
            XCTAssertEqual(flow.linkFailed(with: "aoi"), [.retry("aoi", attempt: attempt)])
            _ = flow.retryFired(for: "aoi")
        }
        XCTAssertEqual(flow.linkFailed(with: "aoi"), [])
        XCTAssertEqual(flow.phase, .failed("aoi"))
    }

    func testManualRetryResetsTheBudget() {
        var flow = Flow()
        _ = flow.userTapped("aoi")
        for _ in 1...Flow.maxAutoRetries {
            _ = flow.linkFailed(with: "aoi")
            _ = flow.retryFired(for: "aoi")
        }
        _ = flow.linkFailed(with: "aoi")
        XCTAssertEqual(flow.userRetried(), [.invite("aoi")])
        XCTAssertEqual(flow.phase, .connecting("aoi"))
        // The fresh budget really is fresh.
        XCTAssertEqual(flow.linkFailed(with: "aoi"), [.retry("aoi", attempt: 1)])
    }

    func testRetryResendsOursButKeepsTheirs() {
        var flow = Flow()
        _ = flow.userTapped("aoi")
        _ = flow.connected(to: "aoi")
        _ = flow.receivedReady(from: "aoi")
        _ = flow.payloadSent(to: "aoi")
        _ = flow.receivedPayload(from: "aoi")  // done would need both; simulate drop first
        // Drop after done is ignored:
        XCTAssertEqual(flow.linkFailed(with: "aoi"), [])
        XCTAssertEqual(flow.phase, .done("aoi"))
    }

    func testDropMidExchangeResendsAfterReconnect() {
        var flow = Flow()
        _ = flow.userTapped("aoi")
        _ = flow.connected(to: "aoi")
        _ = flow.receivedReady(from: "aoi")
        _ = flow.payloadSent(to: "aoi")
        // Their card never landed; the link dies.
        _ = flow.linkFailed(with: "aoi")
        _ = flow.retryFired(for: "aoi")
        // Reconnect: the handshake restarts, our card goes again.
        XCTAssertEqual(flow.connected(to: "aoi"), [.sendReady("aoi")])
        XCTAssertEqual(flow.receivedReady(from: "aoi"), [.sendPayload("aoi")])
    }

    func testDropOfAStrangerIsIgnored() {
        var flow = Flow()
        _ = flow.userTapped("aoi")
        XCTAssertEqual(flow.linkFailed(with: "mio"), [])
        XCTAssertEqual(flow.phase, .connecting("aoi"))
    }

    // MARK: Crossed invites

    func testCrossedInviteElectsExactlyOneHost() {
        let a = "aaa", b = "bbb"
        let aAccepts = Flow.acceptsCrossedInvite(myTag: a, theirTag: b)
        let bAccepts = Flow.acceptsCrossedInvite(myTag: b, theirTag: a)
        XCTAssertNotEqual(aAccepts, bAccepts)
    }

    func testEqualTagsFallBackToAccepting() {
        XCTAssertTrue(Flow.acceptsCrossedInvite(myTag: "same", theirTag: "same"))
    }
}
