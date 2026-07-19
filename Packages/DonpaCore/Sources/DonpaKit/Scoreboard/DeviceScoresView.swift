import DonpaCore
import SwiftUI

/// **Scores by device** — the synced household, each device with its own
/// contribution (wins, games, playtime): the record by WHERE it was earned,
/// not a device manager. Registry entries name the rows; a blob whose device
/// never published one (pre-registry) still shows, unnamed, so the rows
/// always partition the household total.
struct DeviceScoresView: View {
    @ObservedObject var scoreboard: Scoreboard
    @Environment(\.dismiss) private var dismiss

    /// One device's row: registry identity (when known) + its own totals.
    struct Row: Identifiable, Equatable {
        let id: String
        /// nil = a blob with no registry entry (a device from before the
        /// registry shipped, or one whose entry was cleaned up).
        var info: DeviceInfo?
        var summary: DeviceScoreSummary
        var isThisDevice: Bool
    }

    @State private var rows: [Row] = []

    var body: some View {
        SheetScaffold(
            "Scores by device", macMinWidth: 340, macIdealWidth: 400, iosScrolls: true
        ) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows) { row in
                    DeviceScoreRow(row: row)
                    if row.id != rows.last?.id { Divider() }
                }
            }
        }
        .escDismisses { dismiss() }
        .onAppear(perform: load)
    }

    /// Snapshot on open — the sheet is a reading, not a live feed (the
    /// registry itself refreshes at most daily anyway).
    private func load() {
        let tables = scoreboard.perDeviceRecords()
        let ownID = scoreboard.ownDeviceID
        let known = DeviceRegistry(cloud: UbiquitousDeviceRegistry(), deviceID: ownID)
            .knownDevices()
        rows = Self.assemble(tables: tables, known: known, ownID: ownID)
        // The own registry entry can lag the first sync-on session — name this
        // device from live facts rather than showing it "unknown".
        if let i = rows.firstIndex(where: { $0.isThisDevice && $0.info == nil }) {
            let facts = DeviceFacts.current()
            rows[i].info = DeviceInfo(
                id: ownID, name: facts.name, model: facts.model,
                deviceClass: facts.deviceClass, firstSeen: Date(), lastActive: Date())
        }
    }

    /// Pure assembly (tested headless): every score table gets a row, named
    /// when the registry knows the device; registry-only devices (no scores
    /// yet) show too. This device first, then newest-active, ghosts last.
    static func assemble(
        tables: [String: [String: ScoreRecord]], known: [DeviceInfo], ownID: String
    ) -> [Row] {
        let infoByID = Dictionary(uniqueKeysWithValues: known.map { ($0.id, $0) })
        var rows = tables.map { id, records in
            Row(
                id: id, info: infoByID[id], summary: DeviceScoreSummary(records: records),
                isThisDevice: id == ownID)
        }
        for info in known where tables[info.id] == nil {
            rows.append(
                Row(
                    id: info.id, info: info, summary: DeviceScoreSummary(records: [:]),
                    isThisDevice: info.id == ownID))
        }
        return rows.sorted { a, b in
            if a.isThisDevice != b.isThisDevice { return a.isThisDevice }
            switch (a.info, b.info) {
            case (let x?, let y?):
                if x.lastActive != y.lastActive { return x.lastActive > y.lastActive }
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): break
            }
            return a.id < b.id
        }
    }
}

/// One device's line: class icon, name (+ "This device"), coarse activity,
/// and its own tally on the trailing edge.
private struct DeviceScoreRow: View {
    let row: DeviceScoresView.Row

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    name.font(.body.weight(.medium))
                    if row.isThisDevice {
                        Text("This device", bundle: .module)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                }
                // The badge covers this device; a relative stamp would also
                // read more precisely than the registry's daily refresh is.
                if !row.isThisDevice, let active = activity {
                    Text("Active \(active)", bundle: .module)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(row.summary.wins) wins", bundle: .module)
                    .font(.subheadline.weight(.semibold))
                if row.summary.playtimeCentiseconds > 0 {
                    Text(
                        verbatim: ScoreboardView.durationLabel(
                            row.summary.playtimeCentiseconds)
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var name: Text {
        if let info = row.info { return Text(verbatim: info.name) }
        return Text("Unknown device", bundle: .module)
    }

    private var icon: String {
        switch row.info?.deviceClass {
        case .phone: return "iphone"
        case .pad: return "ipad"
        case .mac: return "desktopcomputer"
        case nil: return "questionmark.circle"
        }
    }

    /// Coarse by design — the registry refreshes at most daily, so a
    /// timestamp would suggest precision the data doesn't have.
    private var activity: String? {
        guard let info = row.info else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: info.lastActive, relativeTo: Date())
    }
}
