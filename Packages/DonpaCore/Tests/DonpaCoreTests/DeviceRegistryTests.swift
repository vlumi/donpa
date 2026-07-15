import XCTest

@testable import DonpaCore

@MainActor
final class DeviceRegistryTests: XCTestCase {
    private final class MockCloud: CloudDeviceRegistry {
        var isAvailable = true
        var entries: [String: Data] = [:]
        var writes = 0

        func writeOwnEntry(_ data: Data, deviceID: String) {
            entries[deviceID] = data
            writes += 1
        }
        func deleteOwnEntry(deviceID: String) { entries[deviceID] = nil }
        func readAllEntries() -> [String: Data] { entries }
    }

    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let facts = DeviceInfo.Facts(name: "Neo", model: "Mac16,10", deviceClass: .mac)

    private func registry(_ cloud: MockCloud) -> DeviceRegistry {
        DeviceRegistry(cloud: cloud, deviceID: "dev-a")
    }

    func testPublishesWhenSyncOnRemovesWhenOff() {
        let cloud = MockCloud()
        let reg = registry(cloud)
        reg.refreshOwnEntry(syncEnabled: true, describe: { facts }, now: t0)
        XCTAssertNotNil(cloud.entries["dev-a"])

        reg.refreshOwnEntry(syncEnabled: false, describe: { facts }, now: t0)
        XCTAssertNil(cloud.entries["dev-a"], "sync off mirrors the stats blob removal")
    }

    func testFreshEntryIsNotRewritten() {
        let cloud = MockCloud()
        let reg = registry(cloud)
        reg.refreshOwnEntry(syncEnabled: true, describe: { facts }, now: t0)
        reg.refreshOwnEntry(
            syncEnabled: true, describe: { facts },
            now: t0.addingTimeInterval(DeviceRegistry.refreshInterval / 2))
        XCTAssertEqual(cloud.writes, 1)

        // Stale → freshened; firstSeen survives.
        let later = t0.addingTimeInterval(DeviceRegistry.refreshInterval * 2)
        reg.refreshOwnEntry(syncEnabled: true, describe: { facts }, now: later)
        XCTAssertEqual(cloud.writes, 2)
        let entry = reg.knownDevices().first
        XCTAssertEqual(entry?.firstSeen, t0)
        XCTAssertEqual(entry?.lastActive, later)
    }

    func testChangedFactsRewriteImmediately() {
        let cloud = MockCloud()
        let reg = registry(cloud)
        reg.refreshOwnEntry(syncEnabled: true, describe: { facts }, now: t0)
        reg.refreshOwnEntry(
            syncEnabled: true,
            describe: {
                DeviceInfo.Facts(
                    name: "Renamed", model: facts.model, deviceClass: facts.deviceClass)
            },
            now: t0.addingTimeInterval(60))
        XCTAssertEqual(cloud.writes, 2)
        XCTAssertEqual(reg.knownDevices().first?.name, "Renamed")
    }

    func testKnownDevicesSortsNewestActiveFirstAndSkipsGarbage() {
        let cloud = MockCloud()
        cloud.entries["junk"] = Data("not json".utf8)
        let old = DeviceInfo(
            id: "dev-b", name: "Phone", model: "iPhone17,3", deviceClass: .phone,
            firstSeen: t0, lastActive: t0)
        cloud.entries["dev-b"] = try? JSONEncoder().encode(old)
        let reg = registry(cloud)
        reg.refreshOwnEntry(
            syncEnabled: true, describe: { facts }, now: t0.addingTimeInterval(60))

        let devices = reg.knownDevices()
        XCTAssertEqual(devices.map(\.id), ["dev-a", "dev-b"])
    }
}
