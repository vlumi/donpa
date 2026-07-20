import Foundation

/// Which device class earned a displayed best time — the Record's attribution
/// reader, built once per sheet open from the per-device tables plus the
/// registry's classes. Because each device's table carries only its own
/// times, a merged display entry traces back by simple membership.
///
/// Attribution shows only when it is UNAMBIGUOUS: nil for a time carried by
/// devices of different classes, for a pre-registry blob (no class on file),
/// and for a single-device household, where a glyph would be noise.
public struct DeviceAttribution: Sendable {
    private let tables: [String: [String: ScoreRecord]]
    private let classes: [String: DeviceInfo.DeviceClass]
    private let meaningful: Bool

    public init(
        tables: [String: [String: ScoreRecord]],
        classes: [String: DeviceInfo.DeviceClass]
    ) {
        self.tables = tables
        self.classes = classes
        meaningful = tables.count > 1
    }

    /// The single class that owns this (time, date) entry for the config, or
    /// nil when unknown or ambiguous. Timestamps make collisions across
    /// devices practically ties-only — and a cross-class tie stays blank.
    public func deviceClass(
        for time: BestTime, config key: String
    ) -> DeviceInfo.DeviceClass? {
        guard meaningful else { return nil }
        var found: Set<DeviceInfo.DeviceClass> = []
        for (id, table) in tables {
            guard let record = table[key],
                record.best == time || record.topTimes.contains(time)
            else { continue }
            guard let deviceClass = classes[id] else { return nil }
            found.insert(deviceClass)
        }
        return found.count == 1 ? found.first : nil
    }
}
