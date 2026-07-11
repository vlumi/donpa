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
        case .tab: moveZone(1)
        case .backTab: moveZone(-1)
        case .down: moveRowFocus(1)
        case .up: moveRowFocus(-1)
        case .left: operateZone(-1)
        case .right: operateZone(1)
        case .enter: activateRow()
        case .escape:
            dismiss()
        case .family(let n): pickFilterFamily(n)
        case .character(let ch): handleLetter(ch)
        }
    }

    /// Tab moves BETWEEN the sheet's control zones (wrapping); arrows operate
    /// within one — rows walk the table, ←/→ cycle the focused filter.
    private func moveZone(_ delta: Int) {
        let zones = ScoreboardView.KeyZone.allCases
        let i = zones.firstIndex(of: keyZone) ?? 0
        keyZone = zones[(i + delta + zones.count) % zones.count]
    }

    private func operateZone(_ step: Int) {
        switch keyZone {
        case .rows: break  // ←/→ have no meaning on a table row
        case .family:
            let all = BoardFamily.allCases
            guard let i = all.firstIndex(of: filterFamily) else { return }
            filterFamily = all[min(max(i + step, 0), all.count - 1)]
            expandedKey = nil
            keyRowKey = nil
        case .edges:
            guard filterFamily == .grid || filterFamily == .hive else { return }
            filterEdges = filterEdges == .flat ? .round : .flat
            expandedKey = nil
            keyRowKey = nil
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
    private func activateRow() {
        if keyZone == .rows, let key = keyRowKey { toggleExpanded(key) }
    }

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
