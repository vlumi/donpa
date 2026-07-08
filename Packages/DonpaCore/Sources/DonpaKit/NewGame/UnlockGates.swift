import DonpaCore
import SwiftUI

/// The picker's view of progressive gating: a records snapshot behind the
/// `UnlockEngine` predicates, plus the teaser copy. `open` (nil records) means
/// no gating at all — the default for previews/tests and any caller that
/// doesn't wire a scoreboard, so gating is strictly opt-in per surface.
struct UnlockGates {
    /// nil = everything unlocked (no gating on this surface).
    var records: [String: ScoreRecord]?

    static let open = UnlockGates(records: nil)

    func size(_ size: BoardSize) -> Bool {
        records.map { UnlockEngine.sizeUnlocked(size, records: $0) } ?? true
    }
    func rank(_ rank: Density) -> Bool {
        records.map { UnlockEngine.rankUnlocked(rank, records: $0) } ?? true
    }
    func family(_ family: BoardFamily) -> Bool {
        records.map { UnlockEngine.familyUnlocked(family, records: $0) } ?? true
    }
    func edges(_ edges: BoardEdges) -> Bool {
        records.map { UnlockEngine.edgesUnlocked(edges, records: $0) } ?? true
    }
    func config(_ config: GameConfig) -> Bool {
        records.map { UnlockEngine.unlocked(config, records: $0) } ?? true
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
