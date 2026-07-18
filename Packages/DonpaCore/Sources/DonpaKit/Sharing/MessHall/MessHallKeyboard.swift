#if os(macOS)
import DonpaCore
import SwiftUI

// Split from MessHallView, which is why the @State it drives is internal there
// (Swift `private` is file-scoped).

extension MessHallView {
    func handleKey(_ key: KeyCatcher.Key) {
        switch key {
        case .tab, .backTab, .down, .up, .left, .right: handleMove(key)
        case .enter: confirmOrActivate()
        case .space: activateFocusedZone()
        case .escape: dismiss()
        case .click: keys.enter(nil)  // mouse takes over; the ring stands down
        case .character(let ch): handleLetter(ch)
        case .family: break  // no numbered surfaces here
        }
    }

    private func handleMove(_ key: KeyCatcher.Key) {
        switch key {
        case .tab: cycleZone(1)
        case .backTab: cycleZone(-1)
        case .down: if keys.zone == .rows { keys.move(1, count: focusedRowCount) }
        case .up: if keys.zone == .rows { keys.move(-1, count: focusedRowCount) }
        default: break
        }
    }

    /// Mirrors the render predicates, so Tab can't reach a hidden control.
    private var visibleZones: [KeyZone] {
        var zones = KeyZone.allCases
        if !cardHasLink { zones.removeAll { $0 == .nearby } }
        if focusedRowCount == 0 { zones.removeAll { $0 == .rows } }
        return zones
    }

    private func cycleZone(_ delta: Int) {
        switch keys.cycle(delta, through: visibleZones, entering: Self.entry) {
        case .field: cardActivate.fire()  // the name field is the only field
        default: break
        }
    }

    private static func entry(_ zone: KeyZone) -> KeyCursor<KeyZone>.Entry {
        switch zone {
        case .name: return .field
        case .rows: return .list(seed: 0)
        default: return .plain
        }
    }

    /// Return presses the focused control when it's a button (or enters a field);
    /// on the toggle it's the sheet's default — Done.
    private func confirmOrActivate() {
        switch keys.zone {
        case .career, .sync, nil: dismiss()
        case .name, .nearby, .rows:
            activateFocusedZone()
        }
    }

    private func activateFocusedZone() {
        switch keys.zone {
        case .name, .career, .nearby:
            cardActivate.fire()  // the card routes it to its focused control
        case .rows:
            activateFocusedRow(edit: false)
        case .sync:
            syncActivate.fire()
        case nil:
            break
        }
    }

    private func handleLetter(_ ch: Character) {
        switch ch {
        case "e": if keys.zone == .rows { activateFocusedRow(edit: true) }
        case "n": startNearby()
        default: break
        }
    }

    private func startNearby() {
        nearbyURL = currentShareURL().map(NearbyPayload.init)
    }

    private var focusedRowCount: Int { rivals.count }

    private func activateFocusedRow(edit: Bool) {
        guard let index = keys.index, rivals.indices.contains(index) else { return }
        if edit { editingRival = rivals[index] } else { comparingRival = rivals[index] }
    }
}
#endif
