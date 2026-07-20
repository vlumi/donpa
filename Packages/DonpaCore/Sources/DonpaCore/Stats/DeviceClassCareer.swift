import Foundation

/// The career filtered by device class — "how do I play on the couch vs. at
/// the desk". Built from the per-device tables plus the registry's classes;
/// a filtered view merges only that class's tables (the same merge the
/// display uses, so counters and bests keep their semantics). Individual
/// devices were considered and rejected — class is where the insight lives.
public struct DeviceClassCareer: Sendable {
    /// Classes that actually have data, in display order — the filter is
    /// meaningful (and shown) only when two or more exist. A pre-registry
    /// blob has no class: it counts in the unfiltered view only.
    public let availableClasses: [DeviceInfo.DeviceClass]

    private let tables: [String: [String: ScoreRecord]]
    private let classes: [String: DeviceInfo.DeviceClass]

    public init(
        tables: [String: [String: ScoreRecord]],
        classes: [String: DeviceInfo.DeviceClass]
    ) {
        self.tables = tables
        self.classes = classes
        let present = Set(
            tables.compactMap { id, table in table.isEmpty ? nil : classes[id] })
        availableClasses = [.phone, .pad, .mac].filter(present.contains)
    }

    /// The records the career should sum: every table for nil (equals the
    /// household display), or only the class's tables.
    public func records(for deviceClass: DeviceInfo.DeviceClass?) -> [String: ScoreRecord] {
        let selected =
            deviceClass.map { wanted in tables.filter { classes[$0.key] == wanted } }
            ?? tables
        // An empty `mine` makes every selected table an "other": counters sum
        // and bests min/max across exactly the chosen set.
        return StatsMerge.merge(mine: [:], others: selected)
    }
}
