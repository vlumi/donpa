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
        case .down, .tab: moveRowFocus(1)
        case .up, .backTab: moveRowFocus(-1)
        case .enter:
            if let key = keyRowKey { toggleExpanded(key) }
        case .escape:
            dismiss()
        case .family(let n): pickFilterFamily(n)
        case .character(let ch): handleLetter(ch)
        case .left, .right:
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
