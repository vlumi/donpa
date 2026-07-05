import DonpaCore
import XCTest

@testable import DonpaKit

#if os(macOS)
import CoreImage

/// The macOS QR pipeline end-to-end: a share URL → `QRCode` image → `CIImage` →
/// `ScanShareView.decodeQR` reads back the exact same string. Guards that the
/// generate/scan pair actually agree (a wrong correction level or a scaling bug
/// would break this even though each half "works").
@MainActor
final class QRRoundTripTests: XCTestCase {
    func testGeneratedQRDecodesBack() throws {
        let identity = ShareIdentity()
        let payload = try identity.makePayload(
            name: "Ville",
            scores: [
                SharedConfigScore(key: "v2|basic|beginner", best: 500, wins: 3, bestProgress: nil)
            ],
            career: nil, issuedAt: Date(timeIntervalSince1970: 1_000_000))
        let url = try ShareLink.url(for: payload)

        // Render at a large scale so the detector has plenty of module resolution.
        let image = try XCTUnwrap(QRCode.ciImage(from: url.absoluteString, scale: 10))
        let decoded = try XCTUnwrap(ScanContent.decodeQR(from: image))

        XCTAssertEqual(decoded, url.absoluteString)
        // And the decoded URL classifies as a clean add against an empty friends list.
        let back = try ShareLink.payload(from: try XCTUnwrap(URL(string: decoded)))
        XCTAssertEqual(FriendMerge.outcome(for: back, existing: []), .add)
    }
}
#endif
