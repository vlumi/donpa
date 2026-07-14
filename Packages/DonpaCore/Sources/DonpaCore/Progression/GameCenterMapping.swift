import Foundation

/// Flattens the internal achievement IDs to ASC definitions: one per one-shot,
/// one per tier step. Wire IDs are LOCKED once the store release goes live;
/// thresholds shown, copy, and images stay tunable on the ASC side.
public enum GameCenterMapping {
    /// The ASC achievement-ID prefix (the app's bundle-ID namespace).
    public static let prefix = "fi.misaki.donpa."

    /// Tier steps are named by THRESHOLD ("miles.wins.100"), not index, so the
    /// ID stays self-describing in ASC.
    public static func wireID(_ id: AchievementID, tier: Int? = nil) -> String {
        guard let tier, let thresholds = id.tierThresholds,
            thresholds.indices.contains(tier - 1)
        else { return prefix + id.rawValue }
        return prefix + id.rawValue + ".\(thresholds[tier - 1])"
    }

    public static var allWireIDs: [String] {
        AchievementID.allCases.flatMap { id -> [String] in
            guard let thresholds = id.tierThresholds else { return [wireID(id)] }
            return (1...thresholds.count).map { wireID(id, tier: $0) }
        }
    }

    public struct Report: Equatable, Sendable {
        public let wireID: String
        public let percent: Double

        public init(wireID: String, percent: Double) {
            self.wireID = wireID
            self.percent = percent
        }
    }

    /// Earned lines at 100, the next unearned tier at its live progress;
    /// zero-progress lines omitted (GC treats unreported as 0). Idempotent: GC
    /// ignores reports that don't increase percentComplete, so retroactive
    /// opt-in just works.
    public static func snapshot(
        earned: [AchievementID: Int], records: [String: ScoreRecord]
    ) -> [Report] {
        var reports: [Report] = []
        for id in AchievementID.allCases {
            let earnedTier = earned[id] ?? 0
            guard let thresholds = id.tierThresholds else {
                if earnedTier > 0 { reports.append(Report(wireID: wireID(id), percent: 100)) }
                continue
            }
            for tier in 1...thresholds.count where tier <= earnedTier {
                reports.append(Report(wireID: wireID(id, tier: tier), percent: 100))
            }
            let next = earnedTier + 1
            if next <= thresholds.count,
                let progress = AchievementEngine.progress(for: id, records: records)
            {
                let percent = min(
                    99, Double(progress.current) / Double(thresholds[next - 1]) * 100)
                if percent > 0 {
                    reports.append(Report(wireID: wireID(id, tier: next), percent: percent))
                }
            }
        }
        return reports
    }
}
