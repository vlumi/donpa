import XCTest

@testable import DonpaCore

/// Shared fake: the marker "keychain" as a plain var — `stored` surviving or
/// vanishing models same-hardware vs. new-hardware restores.
final class FakeInstallMarker: InstallMarkerStore {
    var stored: String?
    private(set) var mints = 0

    init(stored: String? = nil) {
        self.stored = stored
    }

    func read() -> String? { stored }

    @discardableResult
    func mint() -> String {
        mints += 1
        let token = "marker-\(mints)"
        stored = token
        return token
    }
}

/// The migration detector: the DeviceID travels with the data (UserDefaults),
/// the marker stays on the hardware (Keychain) — disagreement is the signal.
@MainActor
final class CloneDetectionTests: XCTestCase {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "clone-\(UUID().uuidString)")!
    }

    func testAssessMatrix() {
        // Fresh install: nothing anywhere.
        XCTAssertEqual(
            CloneDetection.assess(
                hasStoredDeviceID: false, markerMinted: false, markerPresent: false),
            .firstRun)
        // Pre-feature install upgrading in place: ID but no marker history.
        XCTAssertEqual(
            CloneDetection.assess(
                hasStoredDeviceID: true, markerMinted: false, markerPresent: false),
            .established)
        // Normal launch: everything agrees.
        XCTAssertEqual(
            CloneDetection.assess(
                hasStoredDeviceID: true, markerMinted: true, markerPresent: true),
            .established)
        // The data (ID + minted flag) arrived, the hardware marker did not:
        // this install was restored/transferred onto different hardware.
        XCTAssertEqual(
            CloneDetection.assess(
                hasStoredDeviceID: true, markerMinted: true, markerPresent: false),
            .migrated)
    }

    func testBootstrapSettlesMarkerOnFreshAndUpgradedInstalls() {
        let d = defaults()
        let marker = FakeInstallMarker()

        // Fresh install: mints and flags.
        XCTAssertEqual(CloneDetection.bootstrap(defaults: d, marker: marker), .firstRun)
        XCTAssertNotNil(marker.read())
        XCTAssertTrue(d.bool(forKey: CloneDetection.markerMintedKey))

        // Next launch: established, no re-mint.
        _ = DeviceID.current(in: d)
        XCTAssertEqual(CloneDetection.bootstrap(defaults: d, marker: marker), .established)
        XCTAssertEqual(marker.mints, 1)
    }

    func testUpgradeInPlaceNeverReadsAsMigration() {
        let d = defaults()
        _ = DeviceID.current(in: d)  // an old install: ID, no marker history
        let marker = FakeInstallMarker()
        XCTAssertEqual(CloneDetection.bootstrap(defaults: d, marker: marker), .established)
        // …and it settles the marker so future launches stay established.
        XCTAssertEqual(marker.mints, 1)
    }

    func testMigrationIsDetectedAndLeftUnsettled() {
        // Simulate the restore: defaults (ID + minted flag) came along, the
        // ThisDeviceOnly marker did not.
        let d = defaults()
        _ = DeviceID.current(in: d)
        d.set(true, forKey: CloneDetection.markerMintedKey)
        let marker = FakeInstallMarker(stored: nil)

        XCTAssertEqual(CloneDetection.bootstrap(defaults: d, marker: marker), .migrated)
        // The verdict must NOT self-settle — the user's continue/fork choice
        // decides. A second launch still says migrated.
        XCTAssertEqual(marker.mints, 0)
        XCTAssertEqual(CloneDetection.bootstrap(defaults: d, marker: marker), .migrated)
    }

    func testContinueAsBeforeAdoptsTheHardware() {
        let d = defaults()
        _ = DeviceID.current(in: d)
        d.set(true, forKey: CloneDetection.markerMintedKey)
        let marker = FakeInstallMarker(stored: nil)
        _ = CloneDetection.bootstrap(defaults: d, marker: marker)

        let id = DeviceID.current(in: d)
        CloneDetection.acceptContinuation(defaults: d, marker: marker)
        XCTAssertEqual(CloneDetection.bootstrap(defaults: d, marker: marker), .established)
        XCTAssertEqual(DeviceID.current(in: d), id, "continuing keeps the identity")
    }
}
