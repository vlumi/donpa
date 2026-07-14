import XCTest

@testable import DonpaKit

@MainActor
final class LaunchActionRouterTests: XCTestCase {
    func testDispatchBeforeRegistrationIsHeldAndDrainedOnce() {
        let router = LaunchActionRouter()
        router.dispatch(.startDrills)

        var received: [LaunchActionRouter.Action] = []
        router.register { received.append($0) }
        XCTAssertEqual(received, [.startDrills])

        router.register { received.append($0) }
        XCTAssertEqual(received, [.startDrills], "drained action must not replay")
    }

    func testDispatchAfterRegistrationIsImmediate() {
        let router = LaunchActionRouter()
        var received: [LaunchActionRouter.Action] = []
        router.register { received.append($0) }
        router.dispatch(.continueBoard)
        XCTAssertEqual(received, [.continueBoard])
    }
}
