#if os(macOS)
import DonpaCore
import SwiftUI

/// The Service Record's keyboard driving (macOS) — the New Game popup's
/// vocabulary: Tab cycles the visible zones, arrows move within one, ←/→
/// (and Space) operate the focused control, Return presses buttons (else
/// Done), ⌘1–⌘4 pick the family filter, E flips Flat/Round, P plays the
/// focused board. Split from ScoreboardView.swift because Swift `private` is
/// file-scoped.
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

    /// Return follows the desktop convention: it presses the focused control
    /// when that control is a button (rows, medals, Manage rivals); anywhere
    /// else it's the sheet's default — Done.
    private func confirmOrActivate() {
        switch keys.zone {
        case .rows, .medals, .manage: activateZone()
        case .career, .breakdown, .family, .edges, .rivals, .sync, nil: dismiss()
        }
    }

    /// The medals HEADER is the zone's landing spot and a real disclosure
    /// button: Return/Space toggles the fold either way (persisted); the
    /// focus stays on the header so Return can immediately toggle back.
    private func toggleMedalsCollapse() {
        settings.medalsCollapsed.toggle()
        keys.index = nil
    }

    /// Space toggles/steps the focused control: segmented zones step forward
    /// (like Settings), buttons and rows activate.
    private func operateOrActivate() {
        switch keys.zone {
        case .breakdown, .family, .edges, .rivals: operateZone(1)
        default: activateZone()
        }
    }

    /// The zones actually rendered right now — the skip logic and the render
    /// predicates share these gates, so Tab can't reach a hidden control (or
    /// miss a visible one).
    private var visibleZones: [ScoreboardView.KeyZone] {
        var zones = ScoreboardView.KeyZone.allCases
        if !PlayDistributionView.hasData(scoreboard) {
            zones.removeAll { $0 == .breakdown }
        }
        if achievements == nil { zones.removeAll { $0 == .medals } }
        if !(filterFamily == .grid || filterFamily == .hive) {
            zones.removeAll { $0 == .edges }
        }
        if friends.friends.isEmpty {
            zones.removeAll { $0 == .rivals || $0 == .manage }
        } else if onMessHall == nil {
            zones.removeAll { $0 == .manage }
        }
        return zones
    }

    private func cycleZone(_ delta: Int) {
        keys.cycle(delta, through: visibleZones, entering: entry)
        // Rows keep STRING-keyed satellite focus (self-heals across filter
        // changes) — seed it the same way the first arrow press would.
        if keys.zone == .rows, keyRowKey == nil { seedRowFocus() }
    }

    /// Medals land on the HEADER (ring there; ↓ enters the grid) — the one
    /// zone whose landing spot is a control of its own.
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

    /// ↓ from the header enters the grid; ↑ from the first medal returns to
    /// the header (folded: the focus stays on the header). One stop past the
    /// last medal is the Game Center toggle in the footer.
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
        case .career, .manage, .rows, .sync, nil: break
        case .breakdown:
            breakdownMetric = breakdownMetric == .playtime ? .games : .playtime
        case .medals:
            moveMedalFocus(step)
        case .rivals:
            // ←/→ walk the comparison scope: All rivals, then each squad.
            let options: [String?] = [nil] + friends.groups.map(\.id)
            let i = options.firstIndex(of: rivalGroupID) ?? 0
            rivalGroupID = options[min(max(i + step, 0), options.count - 1)]
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
        case .career, .breakdown, .family, .edges, .rivals, nil:
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

    /// E flips Flat/Round (where the family has edges); P plays the focused board.
    private func handleLetter(_ ch: Character) {
        switch ch {
        case "e":
            guard filterFamily == .grid || filterFamily == .hive else { return }
            filterEdges = filterEdges == .flat ? .round : .flat
            expandedKey = nil
            keyRowKey = nil
        case "p":
            // Only with the rows zone focused — the row ring is invisible
            // from other zones, and P would start a game on an unseen board.
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

    /// Step the focus; the first press seeds it instead.
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

    /// First landing: the current config's row (the "you are here" band) when
    /// it's in this list, else the first row.
    private func seedRowFocus() {
        let configKeys = orderedConfigs.map(\.storageKey)
        keyRowKey = configKeys.first(where: { $0 == currentConfigKey }) ?? configKeys.first
    }
}
#endif
