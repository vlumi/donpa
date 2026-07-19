#if os(macOS)
import DonpaCore
import SwiftUI

/// The Service Record's keyboard driving (macOS), sharing the New Game popup's
/// vocabulary: Tab cycles the visible zones, arrows move within one, ←/→ and
/// Space operate the focused control, Return presses buttons (else Done),
/// ⌘1–⌘4 pick the family, E flips Flat/Round, P plays the focused board.
extension ScoreboardView {
    func handleKey(_ key: KeyCatcher.Key) {
        switch key {
        case .tab, .backTab, .down, .up, .left, .right: handleMove(key)
        case .enter: confirmOrActivate()
        case .space: operateOrActivate()
        case .escape: dismiss()
        case .click: keys.enter(nil)  // mouse takes over; the ring stands down
        case .family(let n): pickFilterFamily(n)
        case .character(let ch): handleLetter(ch)
        }
    }

    private func handleMove(_ key: KeyCatcher.Key) {
        switch key {
        case .tab: cycleZone(1)
        case .backTab: cycleZone(-1)
        case .down: moveWithinZone(1)
        case .up: moveWithinZone(-1)
        case .left: operateZone(-1)
        case .right: operateZone(1)
        default: break
        }
    }

    /// Return presses the focused control when it's a button (rows, medals,
    /// Manage rivals); anywhere else it's the sheet's default — Done.
    private func confirmOrActivate() {
        switch keys.zone {
        case .rows, .medals, .manage, .devices: activateZone()
        case .career, .breakdown, .family, .edges, .sync, nil: dismiss()
        }
    }

    /// Focus stays on the header, so Return can immediately toggle back.
    private func toggleMedalsCollapse() {
        settings.medalsCollapsed.toggle()
        keys.index = nil
    }

    /// Space steps segmented zones forward (like Settings); buttons and rows activate.
    private func operateOrActivate() {
        switch keys.zone {
        case .breakdown, .family, .edges: operateZone(1)
        default: activateZone()
        }
    }

    /// The zones actually rendered right now — shared with the render
    /// predicates, so Tab can't reach a hidden control or miss a visible one.
    private var visibleZones: [ScoreboardView.KeyZone] {
        var zones = ScoreboardView.KeyZone.allCases
        if !PlayDistributionView.hasData(scoreboard) {
            zones.removeAll { $0 == .breakdown }
        }
        if achievements == nil { zones.removeAll { $0 == .medals } }
        if !(filterFamily == .grid || filterFamily == .hive) {
            zones.removeAll { $0 == .edges }
        }
        if friends.friends.isEmpty || onMessHall == nil {
            zones.removeAll { $0 == .manage }
        }
        if !settings.syncScores { zones.removeAll { $0 == .devices } }
        return zones
    }

    private func cycleZone(_ delta: Int) {
        keys.cycle(delta, through: visibleZones, entering: entry)
        // Seed the row focus the same way the first arrow press would.
        if keys.zone == .rows, keyRowKey == nil { seedRowFocus() }
    }

    private func entry(_ zone: ScoreboardView.KeyZone) -> KeyCursor<KeyZone>.Entry {
        .plain
    }

    private func moveWithinZone(_ delta: Int) {
        switch keys.zone {
        case .rows: moveRowFocus(delta)
        case .medals:
            moveMedalFocus(delta)
        default: break
        }
    }

    /// ↓ from the header enters the grid; ↑ from the first medal returns to the
    /// header. One stop past the last medal is the Game Center toggle.
    private func moveMedalFocus(_ delta: Int) {
        guard !settings.medalsCollapsed else { return }
        if keys.index == 0, delta < 0 {
            keys.index = nil
            return
        }
        keys.move(delta, count: AchievementID.allCases.count + 1)
    }

    private func operateZone(_ step: Int) {
        switch keys.zone {
        case .career, .manage, .rows, .sync, .devices, nil: break
        case .breakdown:
            breakdownMetric = breakdownMetric == .playtime ? .games : .playtime
        case .medals:
            moveMedalFocus(step)
        case .family:
            filterFamily = KeyStep.clamped(filterFamily, by: step)
            expandedKey = nil
            keyRowKey = nil
        case .edges:
            filterEdges = filterEdges == .flat ? .round : .flat
            expandedKey = nil
            keyRowKey = nil
        }
    }

    private func activateZone() {
        switch keys.zone {
        case .rows:
            if let key = keyRowKey { toggleExpanded(key) }
        case .medals:
            guard let i = keys.index else { return toggleMedalsCollapse() }  // header
            guard AchievementID.allCases.indices.contains(i) else {
                return gameCenter.setEnabled(!gameCenter.enabled)  // the footer stop
            }
            let id = AchievementID.allCases[i]
            selectedMedal = selectedMedal == id ? nil : id
        case .manage:
            onMessHall?()
        case .sync:
            syncActivate.fire()
        case .devices:
            showingDeviceScores = true
        case .career, .breakdown, .family, .edges, nil:
            break
        }
    }

    private func pickFilterFamily(_ n: Int) {
        let all = BoardFamily.allCases
        guard n <= all.count else { return }
        filterFamily = all[n - 1]
        expandedKey = nil
        keyRowKey = nil
    }

    private func handleLetter(_ ch: Character) {
        switch ch {
        case "e":
            guard filterFamily == .grid || filterFamily == .hive else { return }
            filterEdges = filterEdges == .flat ? .round : .flat
            expandedKey = nil
            keyRowKey = nil
        case "p":
            // Only with the rows zone focused — from other zones the row ring is
            // invisible, and P would start a game on an unseen board.
            guard keys.zone == .rows, let key = keyRowKey,
                let config = orderedConfigs.first(where: { $0.storageKey == key }),
                gates.config(config)
            else { return }
            onPlay?(config)
        default:
            break
        }
    }

    /// The current filter's rows, in display order — the arrows' track.
    private var orderedConfigs: [GameConfig] {
        let edges: BoardEdges =
            filterFamily == .grid || filterFamily == .hive ? filterEdges : .flat
        return Self.groups(family: filterFamily, edges: edges).flatMap(\.configs)
    }

    private func moveRowFocus(_ delta: Int) {
        guard keys.zone == .rows else { return }
        let configKeys = orderedConfigs.map(\.storageKey)
        guard !configKeys.isEmpty else { return }
        guard let current = keyRowKey, let i = configKeys.firstIndex(of: current) else {
            seedRowFocus()
            return
        }
        let next = min(max(i + delta, 0), configKeys.count - 1)
        keyRowKey = configKeys[next]
    }

    /// First landing: the current config's row when present, else the first row.
    private func seedRowFocus() {
        let configKeys = orderedConfigs.map(\.storageKey)
        keyRowKey = configKeys.first(where: { $0 == currentConfigKey }) ?? configKeys.first
    }
}
#endif
