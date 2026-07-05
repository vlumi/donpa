import DonpaCore
import SwiftUI

/// Bridges the live stores to the pure `ScoreComparison`: builds a per-config ranking
/// (you + the selected rivals) and picks the rivals set from the friends list, honoring
/// an optional group filter. `@MainActor` because it reads `Scoreboard`/`FriendsStore`.
@MainActor
enum RivalRanking {
    /// The friends to compare against: everyone, or just one group's members.
    static func rivals(from friends: FriendsStore, group groupID: String?) -> [Friend] {
        guard let groupID else { return friends.friends }
        return friends.members(of: groupID)
    }

    /// Rank you + the given rivals on one config, by best time. `yourName` falls back to
    /// a generic label when you haven't set a share name.
    static func ranking(
        config: GameConfig, scoreboard: Scoreboard, rivals: [Friend], yourName: String
    ) -> ScoreComparison.Ranking {
        let key = config.storageKey
        let rivalPairs = rivals.map { friend in
            (name: friend.displayName, best: friend.scores.first { $0.key == key }?.best)
        }
        return ScoreComparison.rank(
            yourName: yourName, yourBest: scoreboard.best(for: config), rivals: rivalPairs)
    }
}
