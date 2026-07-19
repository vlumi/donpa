import XCTest

@testable import DonpaCore

/// The stats blob is zlib-compressed on write (its JSON is verbose — a maxed-out
/// table runs ~120 KB against iCloud KVS's 1 MB *total* quota; zlib ≈ 6 KB) and
/// sniffed on read, so a plain-JSON blob from a pre-compression build still loads.
@MainActor
final class StatsBlobCompressionTests: XCTestCase {
    private let storeKey = "donpa.stats.v1"

    private func defaults(_ id: String) -> UserDefaults {
        UserDefaults(suiteName: "blob-\(id)-\(UUID().uuidString)")!
    }

    func testPersistedBlobIsCompressedAndRoundTrips() {
        let store = defaults("roundtrip")
        let board = Scoreboard(defaults: store, cloud: nil)
        board.submitWin(4321, for: .beginner)

        let raw = store.data(forKey: storeKey)
        XCTAssertNotNil(raw)
        XCTAssertNotEqual(raw?.first, UInt8(ascii: "{"), "persisted as zlib, not plain JSON")

        // A fresh Scoreboard on the same store reads it back intact.
        let reloaded = Scoreboard(defaults: store, cloud: nil)
        XCTAssertEqual(reloaded.best(for: .beginner), 4321)
        XCTAssertEqual(Scoreboard.decodeEpoch(raw ?? Data()), 1, "epoch survives compression")
    }

    func testPlainJSONBlobStillLoads() {
        // A pre-compression build wrote plain JSON; the sniffing reader passes it
        // through (epoch stamped at the floor so it isn't dropped as pre-wipe data).
        let store = defaults("legacy")
        let key = GameConfig.beginner.storageKey
        let plain = #"{"version":1,"epoch":1,"records":{"\#(key)":{"wins":{"mine":7}}}}"#
        store.set(Data(plain.utf8), forKey: storeKey)

        let board = Scoreboard(defaults: store, cloud: nil)
        XCTAssertEqual(board.wins(for: .beginner), 7, "plain-JSON blobs decode unchanged")
    }

    func testGarbageBlobDecodesToNothing() {
        XCTAssertEqual(Scoreboard.decodeEpoch(Data([0xDE, 0xAD, 0xBE, 0xEF])), 0)
        XCTAssertTrue(Scoreboard.decodeBlob(Data([0xDE, 0xAD, 0xBE, 0xEF])).isEmpty)
        XCTAssertEqual(Scoreboard.decodeEpoch(Data()), 0)
    }
}
