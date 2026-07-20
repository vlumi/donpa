import DonpaCore
import SwiftUI

/// The rivals row under the filters — the door to the Mess hall. (The
/// squad-scope menu that lived here is parked with squads; the comparison
/// always ranks all rivals.) An extension so it doesn't count against
/// `ScoreboardView`'s type-body-length budget.
extension ScoreboardView {
    @ViewBuilder var manageRivalsControl: some View {
        if let onMessHall {
            HStack(spacing: 8) {
                Spacer()
                Button(action: onMessHall) {
                    Text("Manage rivals", bundle: .module).font(.caption)
                }
                .modifier(zoneRing(.manage))
            }
            .padding(.horizontal, Self.rowInset)
        }
    }
}

extension ScoreboardView {
    /// The per-device reading, sync's sibling in the footer — only meaningful
    /// (and only shown) while the household view exists at all.
    @ViewBuilder var deviceScoresDoor: some View {
        if settings.syncScores {
            Button {
                showingDeviceScores = true
            } label: {
                Text("Scores by device", bundle: .module).font(.caption)
            }
            .modifier(zoneRing(.devices))
        }
    }
}

extension ScoreboardView {
    /// Build the per-open device readers (attribution glyphs + the class
    /// career): per-device tables + the registry's classes. Sync off (or a
    /// one-device household) yields readers that change nothing on screen.
    func buildAttribution() {
        guard settings.syncScores else {
            attribution = nil
            classCareer = nil
            return
        }
        let ownID = scoreboard.ownDeviceID
        let known = DeviceRegistry(cloud: UbiquitousDeviceRegistry(), deviceID: ownID)
            .knownDevices()
        let tables = scoreboard.perDeviceRecords()
        let classes = Dictionary(uniqueKeysWithValues: known.map { ($0.id, $0.deviceClass) })
        attribution = DeviceAttribution(tables: tables, classes: classes)
        classCareer = DeviceClassCareer(tables: tables, classes: classes)
    }

    /// What the career sums: the class-filtered view, or the household display.
    var careerRecords: [String: ScoreRecord] {
        guard let careerClass, let classCareer else { return scoreboard.displayRecords }
        return classCareer.records(for: careerClass)
    }

    /// The class choices the keyboard's ←/→ walk (All first); empty when the
    /// filter isn't shown.
    var careerClassOptions: [DeviceInfo.DeviceClass?] {
        guard let classCareer, classCareer.availableClasses.count >= 2 else { return [] }
        return [nil] + classCareer.availableClasses
    }

    /// All / iPhone / iPad / Mac — only when two or more classes have data.
    @ViewBuilder var careerClassPicker: some View {
        if !careerClassOptions.isEmpty {
            Picker(selection: $careerClass) {
                Text("All", bundle: .module).tag(DeviceInfo.DeviceClass?.none)
                ForEach(classCareer?.availableClasses ?? [], id: \.self) { deviceClass in
                    // Product names, not localized terms.
                    Text(verbatim: StatBlock.className(deviceClass))
                        .tag(DeviceInfo.DeviceClass?.some(deviceClass))
                }
            } label: {
                Text("Scores by device", bundle: .module)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Self.rowInset)
        }
    }
}
