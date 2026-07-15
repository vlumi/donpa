import Foundation

/// The scoreboard's on-disk/cloud blob codec: the versioned `StatsFile`
/// envelope, zlib sniffing, epoch decoding, and the migration seam — the
/// format layer under the store API in Scoreboard.swift.
extension Scoreboard {
    /// On-disk envelope: a format `version` wrapping the records, keyed by
    /// `GameConfig.storageKey` (geometry-bearing, so new variants add keys). `epoch`
    /// is the reset generation this blob was written under (see the wipe tombstone
    /// in `StatsSyncCoordinator`); a reader ignores blobs stamped below the current
    /// epoch. Only ever ENCODED (decoding reads the fields via `JSONSerialization` in
    /// `decodeBlob`/`decodeEpoch`, which default a missing epoch to 0), so no
    /// property default is needed here.
    struct StatsFile: Encodable {
        var version: Int
        var records: [String: ScoreRecord]
        var epoch: Int
    }
    /// Bump only for a *breaking* shape change (additive fields decode tolerantly);
    /// then add a `migrated(_:)` step.
    static let currentVersion = 1

    /// Encode as zlib-compressed JSON. The JSON is verbose (a maxed-out table runs
    /// ~120 KB; zlib ≈ 6 KB) and every device's blob shares iCloud KVS's **1 MB
    /// total** quota — compression removes that ceiling for good. (The counters'
    /// `othersTotal` is also encoded although blob readers ignore it — see
    /// `StatsMerge` — but under compression the repetition costs nothing.)
    static func encodeFile(_ records: [String: ScoreRecord], epoch: Int) -> Data? {
        let json = try? JSONEncoder().encode(
            StatsFile(version: currentVersion, records: records, epoch: epoch))
        guard let json else { return nil }
        return (try? (json as NSData).compressed(using: .zlib) as Data) ?? json
    }

    /// Sniff-decompress a stats blob: plain JSON (a pre-compression build's local
    /// store / cloud blob, or a test fixture) starts with `{` and passes through;
    /// anything else is treated as a zlib stream (empty/garbage → empty Data, which
    /// the decoders below turn into "no records" / epoch 0).
    static func decompressIfNeeded(_ data: Data) -> Data {
        guard data.first != UInt8(ascii: "{") else { return data }
        return (try? (data as NSData).decompressed(using: .zlib) as Data) ?? Data()
    }

    /// The reset epoch stamped in a blob (0 if absent / undecodable).
    static func decodeEpoch(_ data: Data) -> Int {
        guard
            let top = try? JSONSerialization.jsonObject(with: decompressIfNeeded(data))
                as? [String: Any]
        else { return 0 }
        return top["epoch"] as? Int ?? 0
    }

    #if DEBUG
    /// Test-only: forge a single-config blob at a specific epoch, to exercise the
    /// stale-epoch rejection path (a returning offline device's pre-wipe blob).
    static func testMakeBlob(wins: Int, for config: GameConfig, epoch: Int) -> Data {
        var rec = ScoreRecord()
        rec.wins.add(wins)
        return encodeFile([config.storageKey: rec], epoch: epoch) ?? Data()
    }
    #endif

    static func load(from defaults: UserDefaults, key: String) -> [String: ScoreRecord] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        // Drop own records written below the reset-epoch floor (pre-upgrade), so the
        // one-off clean slate covers this device's local store, not just the cloud.
        guard decodeEpoch(data) >= StatsSyncCoordinator.epochFloor else { return [:] }
        return decodeBlob(data)
    }

    /// Decode a stats blob (local, or a cloud per-device blob), resilient to old
    /// formats and partial corruption: prefer the versioned envelope (reject a
    /// newer version this build predates); fall back to a legacy bare dict; either
    /// way decode **per entry**, so one bad record is dropped, never the whole table.
    static func decodeBlob(_ data: Data) -> [String: ScoreRecord] {
        func perEntry(_ object: [String: Any]) -> [String: ScoreRecord] {
            var out: [String: ScoreRecord] = [:]
            for (k, v) in object {
                guard
                    let frag = try? JSONSerialization.data(
                        withJSONObject: v, options: [.fragmentsAllowed]),
                    let rec = try? JSONDecoder().decode(ScoreRecord.self, from: frag)
                else { continue }
                out[k] = rec
            }
            return out
        }

        guard
            let top = try? JSONSerialization.jsonObject(with: decompressIfNeeded(data))
                as? [String: Any]
        else { return [:] }

        if let versioned = top["records"] as? [String: Any], let v = top["version"] as? Int {
            if v > currentVersion { return [:] }  // newer = unknown breaking change
            return migrated(perEntry(versioned), from: v)
        }
        // Legacy bare dict (pre-envelope): the records sit at the top level.
        return migrated(perEntry(top), from: 0)
    }

    /// Migration seam. Identity today; transform records up one step per version
    /// here when `currentVersion` is bumped (with fixture tests).
    static func migrated(_ records: [String: ScoreRecord], from version: Int)
        -> [String: ScoreRecord]
    {
        records
    }
}
