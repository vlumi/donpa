#if os(macOS)
import DonpaCore
import SwiftUI

// Split from MessHallView, which is why the @State it drives is internal there
// (Swift `private` is file-scoped).

extension MessHallView {
    /// ⌘1/⌘2 arrive here because the KeyCatcher consumes number equivalents
    /// (they mirror the hidden tab buttons).
    func handleKey(_ key: KeyCatcher.Key) {
        switch key {
        case .tab, .backTab, .down, .up, .left, .right: handleMove(key)
        case .enter: confirmOrActivate()
        case .space: activateFocusedZone()
        case .escape: dismiss()
        case .click: keys.enter(nil)  // mouse takes over; the ring stands down
        case .character(let ch): handleLetter(ch)
        case .family(let n): pickTab(n)
        }
    }

    private func handleMove(_ key: KeyCatcher.Key) {
        switch key {
        case .tab: cycleZone(1)
        case .backTab: cycleZone(-1)
        case .down: if keys.zone == .rows { keys.move(1, count: focusedRowCount) }
        case .up: if keys.zone == .rows { keys.move(-1, count: focusedRowCount) }
        case .left, .right: if keys.zone == .tabs { switchTab() }
        default: break
        }
    }

    /// Mirrors the render predicates, so Tab can't reach a hidden control.
    private var visibleZones: [KeyZone] {
        var zones = KeyZone.allCases
        if !cardHasLink { zones.removeAll { [.nearby, .shareLink, .qr].contains($0) } }
        if tab != .squads { zones.removeAll { $0 == .newSquad } }
        if focusedRowCount == 0 { zones.removeAll { $0 == .rows } }
        return zones
    }

    private func cycleZone(_ delta: Int) {
        switch keys.cycle(delta, through: visibleZones, entering: Self.entry) {
        case .field where keys.zone == .name: cardActivate.fire()
        case .field: newSquadFocused = true
        default: break
        }
    }

    private static func entry(_ zone: KeyZone) -> KeyCursor<KeyZone>.Entry {
        switch zone {
        case .name, .newSquad: return .field
        case .rows: return .list(seed: 0)
        default: return .plain
        }
    }

    /// Return presses the focused control when it's a button (or enters a field);
    /// on the toggles and the tab strip it's the sheet's default — Done.
    private func confirmOrActivate() {
        switch keys.zone {
        case .career, .tabs, .sync, nil: dismiss()
        case .name, .nearby, .shareLink, .qr, .newSquad, .rows, .addRival:
            activateFocusedZone()
        }
    }

    private func activateFocusedZone() {
        switch keys.zone {
        case .name, .career, .nearby, .shareLink, .qr:
            cardActivate.fire()  // the card routes it to its focused control
        case .tabs:
            switchTab()
        case .newSquad:
            newSquadFocused = true
        case .rows:
            activateFocusedRow(edit: false)
        case .addRival:
            scanning = true
        case .sync:
            syncActivate.fire()
        case nil:
            break
        }
    }

    private func handleLetter(_ ch: Character) {
        switch ch {
        case "e": if keys.zone == .rows { activateFocusedRow(edit: true) }
        case "a": scanning = true
        case "n": startNearby()
        default: break
        }
    }

    private func pickTab(_ n: Int) {
        switch n {
        case 1: tab = .rivals
        case 2: tab = .squads
        default: return
        }
        keys.index = nil
    }

    private func switchTab() {
        tab = tab == .rivals ? .squads : .rivals
        keys.index = nil
    }

    private func startNearby() {
        nearbyURL = currentShareURL().map(NearbyPayload.init)
    }

    private var focusedRowCount: Int {
        tab == .rivals ? rivals.count : friends.groups.count
    }

    private func activateFocusedRow(edit: Bool) {
        guard let index = keys.index else { return }
        switch tab {
        case .rivals:
            guard rivals.indices.contains(index) else { return }
            if edit { editingRival = rivals[index] } else { comparingRival = rivals[index] }
        case .squads:
            guard friends.groups.indices.contains(index) else { return }
            let group = friends.groups[index]
            if edit {
                editingGroup = group
            } else if !friends.members(of: group.id).isEmpty {
                comparingGroup = group
            }
        }
    }
}
#endif
