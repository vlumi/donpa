import DonpaCore
import SwiftUI

/// The picker's view of progressive gating: a records snapshot behind the
/// `UnlockEngine` predicates, plus the teaser copy. `open` (nil records) means
/// no gating at all — the default for previews/tests and any caller that
/// doesn't wire a scoreboard, so gating is strictly opt-in per surface.
struct UnlockGates {
    /// nil = everything unlocked (no gating on this surface).
    var records: [String: ScoreRecord]?
    /// Launch-time win counts to subtract — the `-donpa.gates.fresh` debug run:
    /// only wins EARNED THIS SESSION count, so a veteran tester experiences the
    /// gates (and the unlock moments) without touching their real records.
    var winsBaseline: [String: Int] = [:]
    /// The Settings "Unlock all boards" bypass: predicates read true and teasers
    /// vanish, but nothing is stored — flipping it off returns to what the
    /// records derive (wins earned meanwhile still counted normally).
    var bypassAll = false

    static let open = UnlockGates(records: nil)

    /// The launch flag: gates pretend the install is fresh (session wins only).
    static var freshRun: Bool {
        ProcessInfo.processInfo.arguments.contains("-donpa.gates.fresh")
    }

    /// The records the predicates actually see (baseline-adjusted; nil = open).
    private var effective: [String: ScoreRecord]? {
        if bypassAll { return nil }
        guard let records, !winsBaseline.isEmpty else { return records }
        return records.filter { key, record in
            record.wins.total - (winsBaseline[key] ?? 0) > 0
        }
    }

    func size(_ size: BoardSize) -> Bool {
        effective.map { UnlockEngine.sizeUnlocked(size, records: $0) } ?? true
    }
    func rank(_ rank: Density) -> Bool {
        effective.map { UnlockEngine.rankUnlocked(rank, records: $0) } ?? true
    }
    func family(_ family: BoardFamily) -> Bool {
        effective.map { UnlockEngine.familyUnlocked(family, records: $0) } ?? true
    }
    func edges(_ edges: BoardEdges) -> Bool {
        effective.map { UnlockEngine.edgesUnlocked(edges, records: $0) } ?? true
    }
    func config(_ config: GameConfig) -> Bool {
        effective.map { UnlockEngine.unlocked(config, records: $0) } ?? true
    }

    /// What a win just opened: the display names of every gate whose predicate
    /// flipped between the two record snapshots — the result panel's sticker.
    static func newlyUnlocked(
        before: [String: ScoreRecord], after: [String: ScoreRecord],
        winsBaseline: [String: Int] = [:]
    ) -> [String] {
        let old = UnlockGates(records: before, winsBaseline: winsBaseline)
        let new = UnlockGates(records: after, winsBaseline: winsBaseline)
        var opened: [String] = []
        for size in BoardSize.allCases where !old.size(size) && new.size(size) {
            opened.append(size.label)
        }
        for rank in Density.allCases where !old.rank(rank) && new.rank(rank) {
            opened.append(rank.label)
        }
        if !old.family(.hive), new.family(.hive) { opened.append(BoardFamily.hive.label) }
        if !old.edges(.round), new.edges(.round) { opened.append(BoardEdges.round.label) }
        return opened
    }

    /// The teaser line for a locked option.
    static func requirementText(_ requirement: UnlockEngine.Requirement) -> String {
        switch requirement {
        case .winSize(let size):
            return String(
                localized: "Win a board at \(size.label) to unlock", bundle: .module,
                comment: "Teaser under a locked size chip; %@ = the size below it")
        case .winRank(let rank):
            return String(
                localized: "Win a \(rank.label) board (S or larger) to unlock",
                bundle: .module,
                comment: "Teaser under a locked rank chip; %@ = the rank below it")
        case .winAnySquare:
            return String(
                localized: "Win any board to unlock the Hive", bundle: .module)
        case .winAtLeastM:
            return String(
                localized: "Win a board at M or larger to unlock Round edges",
                bundle: .module)
        }
    }
}

/// The padlock badge a locked chip/tab/segment wears — SaveDot's corner idiom,
/// opposite corner (bottom-trailing), so a chip can carry both without overlap.
struct LockBadge: ViewModifier {
    let locked: Bool

    func body(content: Content) -> some View {
        content
            .opacity(locked ? 0.45 : 1)
            .overlay(alignment: .bottomTrailing) {
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(2)
                        .background(Circle().fill(.background))
                        .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
                        .offset(x: 3, y: 3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)  // the host's a11y value carries it
                }
            }
    }
}
