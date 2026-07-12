import Foundation

/// One surface's keyboard cursor: the Tab-focused zone plus, for list zones,
/// the focused item index. Pure state and math — the host view supplies the
/// currently VISIBLE zones and item counts, maps each zone to its `Entry`,
/// and runs the side effects itself (focus a field, scroll an anchor).
///
/// The settled vocabulary this encodes: Tab wraps through the visible zones
/// (first Tab enters at the start, Shift-Tab at the end); entering a list
/// zone seeds its item focus so the landing is visible; arrows clamp within
/// a zone.
struct KeyCursor<Zone: Hashable> {
    private(set) var zone: Zone?
    var index: Int?

    /// What entering a zone should trigger in the host view.
    enum Entry: Equatable {
        /// Nothing beyond the zone ring.
        case plain
        /// A list: seed the item focus (0, or e.g. the Record's current row).
        case list(seed: Int)
        /// A text field: the host starts editing (a focused field IS an
        /// editing field).
        case field
    }

    /// Tab / Shift-Tab: wraps through `visible`; from nothing, enters at the
    /// first zone (forward) or the last (backward). Returns the landed
    /// zone's entry action, or nil when there is nothing to focus.
    @discardableResult
    mutating func cycle(
        _ delta: Int, through visible: [Zone],
        entering: (Zone) -> Entry = { _ in .plain }
    ) -> Entry? {
        guard !visible.isEmpty else {
            return enter(nil, entering: entering)
        }
        guard let zone, let i = visible.firstIndex(of: zone) else {
            return enter(delta > 0 ? visible[0] : visible[visible.count - 1], entering: entering)
        }
        return enter(visible[(i + delta + visible.count) % visible.count], entering: entering)
    }

    /// Direct entry (or `nil` to clear); runs the same seeding rule as
    /// `cycle`. Changing zones drops the previous zone's item focus.
    @discardableResult
    mutating func enter(
        _ target: Zone?, entering: (Zone) -> Entry = { _ in .plain }
    ) -> Entry? {
        if target != zone { index = nil }
        zone = target
        guard let target else { return nil }
        let entry = entering(target)
        if case .list(let seed) = entry, index == nil { index = seed }
        return entry
    }

    /// Arrow step within the current zone's list: clamps to `0..<count`,
    /// seeds at 0 on the first press, clears when the list is empty.
    mutating func move(_ delta: Int, count: Int) {
        index = KeyStep.moved(index, by: delta, count: count)
    }
}

/// Clamped stepping along an ordered ladder — segmented pickers and other
/// pick-one controls driven by ←/→.
enum KeyStep {
    /// A value not on the ladder (e.g. a locked entry after gating changed)
    /// steps to the ladder's first entry rather than staying invalid.
    static func clamped<T: Equatable>(_ value: T, by delta: Int, within all: [T]) -> T {
        guard !all.isEmpty else { return value }
        guard let i = all.firstIndex(of: value) else { return all[0] }
        return all[min(max(i + delta, 0), all.count - 1)]
    }

    /// The same over a full `CaseIterable` ladder.
    static func clamped<T: CaseIterable & Equatable>(_ value: T, by delta: Int) -> T {
        clamped(value, by: delta, within: Array(T.allCases))
    }

    /// Clamped list-focus step: seeds at 0 on the first press, clears when
    /// the list is empty — the one arrow-walk rule for zone-less lists too.
    static func moved(_ current: Int?, by delta: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let current else { return 0 }
        return min(max(current + delta, 0), count - 1)
    }
}
