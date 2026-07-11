#if os(macOS)
import DonpaCore
import SwiftUI

/// The Service Record's keyboard driving (macOS) — the New Game popup's
/// vocabulary: arrows move the row focus, Return expands/collapses it,
/// ⌘1–⌘4 pick the family filter, E flips Flat/Round, P starts a game on the
/// focused board. Esc closes (the sheet's cancel action; also handled here in
/// case the catcher owns the event). Split from SheetViews for file length.
extension ScoreboardView {
    func handleKey(_ key: KeyCatcher.Key) {
        switch key {
        case .tab, .backTab, .down, .up, .left, .right: handleMove(key)
        case .enter: confirmOrActivate()
        case .space: activateZone()
        case .escape: dismiss()
        case .family(let n): pickFilterFamily(n)
        case .character(let ch): handleLetter(ch)
        }
    }

    private func handleMove(_ key: KeyCatcher.Key) {
        switch key {
        case .tab: moveZone(1)
        case .backTab: moveZone(-1)
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
        switch keyZone {
        case .rows, .medals, .manage: activateZone()
        case .career, .family, .edges, .rivals, .sync: dismiss()
        }
    }

    /// Tab moves BETWEEN the sheet's control zones (wrapping, skipping an
    /// edges filter the current family doesn't show and rival controls that
    /// aren't rendered); arrows work within one.
    private func moveZone(_ delta: Int) {
        var zones = ScoreboardView.KeyZone.allCases
        if !(filterFamily == .grid || filterFamily == .hive) {
            zones.removeAll { $0 == .edges }
        }
        if friends.friends.isEmpty {
            zones.removeAll { $0 == .rivals || $0 == .manage }
        } else {
            if friends.groups.isEmpty { zones.removeAll { $0 == .rivals } }
            if onMessHall == nil { zones.removeAll { $0 == .manage } }
        }
        let i = zones.firstIndex(of: keyZone) ?? 0
        keyZone = zones[(i + delta + zones.count) % zones.count]
    }

    private func moveWithinZone(_ delta: Int) {
        switch keyZone {
        case .rows: moveRowFocus(delta)
        case .medals: moveMedalFocus(delta)
        default: break
        }
    }

    private func operateZone(_ step: Int) {
        switch keyZone {
        case .career, .manage, .rows, .sync: break
        case .medals: moveMedalFocus(step)
        case .rivals:
            // ←/→ walk the comparison scope: All rivals, then each squad.
            let options: [String?] = [nil] + friends.groups.map(\.id)
            let i = options.firstIndex(of: rivalGroupID) ?? 0
            rivalGroupID = options[min(max(i + step, 0), options.count - 1)]
        case .family:
            let all = BoardFamily.allCases
            guard let i = all.firstIndex(of: filterFamily) else { return }
            filterFamily = all[min(max(i + step, 0), all.count - 1)]
            expandedKey = nil
            keyRowKey = nil
        case .edges:
            filterEdges = filterEdges == .flat ? .round : .flat
            expandedKey = nil
            keyRowKey = nil
        }
    }

    private func activateZone() {
        switch keyZone {
        case .rows:
            if let key = keyRowKey { toggleExpanded(key) }
        case .medals:
            guard let i = keyMedalIndex, AchievementID.allCases.indices.contains(i)
            else { return }
            let id = AchievementID.allCases[i]
            selectedMedal = selectedMedal == id ? nil : id
        case .manage:
            onMessHall?()
        case .sync:
            syncActivateTick += 1
        case .career, .family, .edges, .rivals:
            break
        }
    }

    /// ←/→ browse the medal grid linearly (the adaptive column count isn't
    /// knowable here, so no 2D stepping).
    private func moveMedalFocus(_ delta: Int) {
        let count = AchievementID.allCases.count
        guard count > 0 else { return }
        guard let current = keyMedalIndex else {
            keyMedalIndex = 0
            return
        }
        keyMedalIndex = min(max(current + delta, 0), count - 1)
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
            guard let key = keyRowKey,
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

    /// Step the focus; the first press lands on the current config's row (the
    /// "you are here" band) when it's in this list, else the first row.
    private func moveRowFocus(_ delta: Int) {
        guard keyZone == .rows else { return }
        let keys = orderedConfigs.map(\.storageKey)
        guard !keys.isEmpty else { return }
        guard let current = keyRowKey, let i = keys.firstIndex(of: current) else {
            keyRowKey = keys.first(where: { $0 == currentConfigKey }) ?? keys.first
            return
        }
        let next = min(max(i + delta, 0), keys.count - 1)
        keyRowKey = keys[next]
    }
}
#endif
