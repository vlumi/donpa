#if os(macOS)
import DonpaCore
import SwiftUI

// The Mess hall's keyboard driving — split from MessHallView for the
// file-length budget (the touched state is internal for that reason).

extension MessHallView {
    /// The keyboard-focus ring for a list row (macOS arrow navigation);

    #if os(macOS)
    /// Arrow/Return/E/⌘-number keyboard driving — the Record's vocabulary on
    /// the social lists. ⌘1/⌘2 arrive here because the KeyCatcher consumes
    /// number equivalents; they mirror the hidden tab buttons.
    func handleKey(_ key: KeyCatcher.Key) {
        switch key {
        case .tab: moveZone(1)
        case .backTab: moveZone(-1)
        case .down: moveRowFocus(1)
        case .up: moveRowFocus(-1)
        case .enter, .space: activateFocusedZone()
        case .escape: dismiss()
        case .character(let ch): handleLetter(ch)
        case .family(let n): pickTab(n)
        case .left, .right: if keyZone == .tabs { switchTab() }
        }
    }

    /// E edits the focused row; A opens the scanner; N starts Nearby.
    private func handleLetter(_ ch: Character) {
        switch ch {
        case "e": if keyZone == .rows { activateFocusedRow(edit: true) }
        case "a": scanning = true
        case "n": startNearby()
        default: break
        }
    }

    /// ⌘1/⌘2 mirror the hidden tab buttons (the catcher consumes number
    /// equivalents).
    private func pickTab(_ n: Int) {
        switch n {
        case 1: tab = .rivals
        case 2: tab = .squads
        default: return
        }
        keyRowIndex = nil
    }

    /// Tab moves BETWEEN zones (wrapping, skipping card actions that aren't
    /// visible without a share name); arrows walk the list within its zone,
    /// ←/→ switch the tabs when that zone is focused.
    private func moveZone(_ delta: Int) {
        var zones = KeyZone.allCases
        if settings.shareName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            zones.removeAll { [.nearby, .shareLink, .qr].contains($0) }
        }
        let i = zones.firstIndex(of: keyZone) ?? 0
        keyZone = zones[(i + delta + zones.count) % zones.count]
    }

    private func activateFocusedZone() {
        switch keyZone {
        case .name, .career, .nearby, .shareLink, .qr:
            cardActivateTick += 1  // the card routes it to its focused control
        case .tabs:
            switchTab()
        case .rows:
            activateFocusedRow(edit: false)
        case .addRival:
            scanning = true
        case .sync:
            syncActivateTick += 1
        }
    }

    /// The card control the current zone maps to (its ring + activation target).
    var cardKeyFocus: ShareCardView.KeyFocus? {
        switch keyZone {
        case .name: return .name
        case .career: return .career
        case .nearby: return .nearby
        case .shareLink: return .shareLink
        case .qr: return .qr
        default: return nil
        }
    }

    private func switchTab() {
        tab = tab == .rivals ? .squads : .rivals
        keyRowIndex = nil
    }

    /// Same gate as the card's button: no name → no card to swap.
    private func startNearby() {
        nearbyURL = currentShareURL().map(NearbyPayload.init)
    }

    private var focusedRowCount: Int {
        tab == .rivals ? rivals.count : friends.groups.count
    }

    private func moveRowFocus(_ delta: Int) {
        guard keyZone == .rows, focusedRowCount > 0 else { return }
        guard let current = keyRowIndex else {
            keyRowIndex = 0
            return
        }
        keyRowIndex = min(max(current + delta, 0), focusedRowCount - 1)
    }

    /// Return = the row's tap (compare); E = its pencil (edit).
    private func activateFocusedRow(edit: Bool) {
        guard let index = keyRowIndex else { return }
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
    #endif

}
#endif
