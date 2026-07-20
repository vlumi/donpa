import DonpaCore
import SwiftUI

/// **Scores by device** — the synced household, each device with its own
/// contribution (wins, games, playtime): the record by WHERE it was earned,
/// not a device manager. Registry entries name the rows; a blob whose device
/// never published one (pre-registry) still shows, unnamed, so the rows
/// always partition the household total. Tapping a row edits its nickname —
/// your label, layered over the device's self-published name.
struct DeviceScoresView: View {
    @ObservedObject var scoreboard: Scoreboard
    @ObservedObject var settings: Settings
    @Environment(\.dismiss) private var dismiss

    /// One device's row: registry identity (when known) + its own totals.
    struct Row: Identifiable, Equatable {
        let id: String
        /// nil = a blob with no registry entry (a device from before the
        /// registry shipped, or one whose entry was cleaned up).
        var info: DeviceInfo?
        var nickname: String?
        var summary: DeviceScoreSummary
        var isThisDevice: Bool
    }

    @State private var rows: [Row] = []
    /// The row whose nickname is being edited (sheet item).
    @State private var editing: Row?
    /// The keyboard-focused row's id (macOS); arrows move it, Return edits.
    @State private var focusedRow: String?
    private let nicknames = DeviceNicknames(cloud: UbiquitousDeviceNicknames())

    var body: some View {
        SheetScaffold(
            "Scores by device", macMinWidth: 340, macIdealWidth: 400, iosScrolls: true
        ) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows) { row in
                    Button {
                        focusedRow = nil
                        editing = row
                    } label: {
                        DeviceScoreRow(row: row)
                    }
                    .buttonStyle(.plain)
                    .keyFocusRing(focusedRow == row.id)
                    if row.id != rows.last?.id { Divider() }
                }
            }
        }
        .escDismisses { dismiss() }
        .background(deviceKeyCatcher)
        .onAppear(perform: load)
        .appearanceSheet(item: $editing, settings) { row in
            DeviceNicknameEditor(row: row) { name in
                nicknames.set(name, for: row.id)
                reloadNicknames()
            }
        }
    }

    /// Arrows walk the rows, Return edits the focused one's nickname.
    @ViewBuilder private var deviceKeyCatcher: some View {
        #if os(macOS)
        KeyCatcher(
            onKey: { key in
                switch key {
                case .down, .tab: moveRowFocus(1)
                case .up, .backTab: moveRowFocus(-1)
                case .enter, .space:
                    if let id = focusedRow, let row = rows.first(where: { $0.id == id }) {
                        editing = row
                    } else if key == .enter {
                        dismiss()
                    }
                case .escape: dismiss()
                case .click: focusedRow = nil  // mouse takes over
                default: break
                }
            }, yieldsToTextFields: true)
        #endif
    }

    #if os(macOS)
    private func moveRowFocus(_ delta: Int) {
        guard !rows.isEmpty else { return }
        guard let current = focusedRow, let i = rows.firstIndex(where: { $0.id == current })
        else {
            focusedRow = (delta > 0 ? rows.first : rows.last)?.id
            return
        }
        focusedRow = rows[min(max(i + delta, 0), rows.count - 1)].id
    }
    #endif

    /// Snapshot on open — the sheet is a reading, not a live feed (the
    /// registry itself refreshes at most daily anyway).
    private func load() {
        let tables = scoreboard.perDeviceRecords()
        let ownID = scoreboard.ownDeviceID
        let known = DeviceRegistry(cloud: UbiquitousDeviceRegistry(), deviceID: ownID)
            .knownDevices()
        rows = Self.assemble(
            tables: tables, known: known, ownID: ownID, nicknames: nicknames.all())
        // The own registry entry can lag the first sync-on session — name this
        // device from live facts rather than showing it "unknown".
        if let i = rows.firstIndex(where: { $0.isThisDevice && $0.info == nil }) {
            let facts = DeviceFacts.current()
            rows[i].info = DeviceInfo(
                id: ownID, name: facts.name, model: facts.model,
                deviceClass: facts.deviceClass, firstSeen: Date(), lastActive: Date())
        }
    }

    /// A saved nickname lands in the visible rows without re-reading blobs.
    private func reloadNicknames() {
        let all = nicknames.all()
        for i in rows.indices { rows[i].nickname = all[rows[i].id] }
    }

    /// Pure assembly (tested headless): every score table gets a row, named
    /// when the registry knows the device; registry-only devices (no scores
    /// yet) show too. This device first, then newest-active, ghosts last.
    static func assemble(
        tables: [String: [String: ScoreRecord]], known: [DeviceInfo], ownID: String,
        nicknames: [String: String] = [:]
    ) -> [Row] {
        let infoByID = Dictionary(uniqueKeysWithValues: known.map { ($0.id, $0) })
        var rows = tables.map { id, records in
            Row(
                id: id, info: infoByID[id], nickname: nicknames[id],
                summary: DeviceScoreSummary(records: records), isThisDevice: id == ownID)
        }
        for info in known where tables[info.id] == nil {
            rows.append(
                Row(
                    id: info.id, info: info, nickname: nicknames[info.id],
                    summary: DeviceScoreSummary(records: [:]),
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
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var name: Text {
        if let nickname = row.nickname { return Text(verbatim: nickname) }
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

    /// Day-granular by design — the registry refreshes at most daily, so
    /// "15 hours ago" would claim precision the data doesn't have. Calendar
    /// days, so early-morning yesterday reads "yesterday", not "today".
    private var activity: String? {
        guard let info = row.info else { return nil }
        let calendar = Calendar.current
        let days =
            calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: info.lastActive),
                to: calendar.startOfDay(for: Date())
            ).day ?? 0
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(from: DateComponents(day: -max(0, days)))
    }
}

/// The nickname editor: the device's own name stays visible (it's never
/// overwritten — the rival-alias pattern); every keystroke persists via the
/// save closure, Done just closes.
private struct DeviceNicknameEditor: View {
    let row: DeviceScoresView.Row
    let save: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var nickname: String
    @FocusState private var fieldFocused: Bool

    init(row: DeviceScoresView.Row, save: @escaping (String) -> Void) {
        self.row = row
        self.save = save
        _nickname = State(initialValue: row.nickname ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Device name", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
                deviceName.font(.body)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Nickname", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
                TextField(text: $nickname) {
                    Text("Optional", bundle: .module)
                }
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onChangeCompat(of: nickname) { save($0) }
            }
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Done", bundle: .module)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 300, maxWidth: 380)
        .escDismisses { dismiss() }
        .onAppear { fieldFocused = true }
    }

    private var deviceName: Text {
        if let info = row.info { return Text(verbatim: info.name) }
        return Text("Unknown device", bundle: .module)
    }
}
