import XCTest

@testable import DonpaKit

/// LaunchStores — the single gate deciding real vs ephemeral storage. The test
/// process never carries `-uitest-clean`, so this pins the PRODUCTION side of
/// the gate: real defaults, real sync toggle.
final class LaunchStoresTests: XCTestCase {
    func testProductionLaunchUsesStandardDefaults() {
        XCTAssertFalse(LaunchStores.isClean)
        XCTAssertTrue(LaunchStores.defaults === UserDefaults.standard)
    }

    func testEphemeralFriendsDirIsUniqueAndCreated() {
        let a = LaunchStores.ephemeralFriendsDir()
        let b = LaunchStores.ephemeralFriendsDir()
        XCTAssertNotEqual(a, b)  // per-launch isolation, never a shared file
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        try? FileManager.default.removeItem(at: a)
        try? FileManager.default.removeItem(at: b)
    }
}
