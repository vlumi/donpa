import Foundation

/// The longest-odds forced guess this device has SURVIVED (+ when). Device-owned
/// like `BestTime`: the cross-device view is projected at merge time by taking
/// the min, so the timestamp always travels with its value. This record is what
/// keeps the guess-odds achievements retroactive from stats alone.
public struct LuckiestGuess: Equatable, Sendable, Codable, Comparable {
    /// Survival probability at click time, 0...1 (lower = luckier).
    public var survival: Double
    /// Wall-clock at record time; labeling, not ordering.
    public var achievedAt: Date

    public init(survival: Double, achievedAt: Date) {
        self.survival = survival
        self.achievedAt = achievedAt
    }

    /// Luckier (lower survival) sorts first; equal odds tie-break to the earlier
    /// date so the merge projection is deterministic.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.survival != rhs.survival { return lhs.survival < rhs.survival }
        return lhs.achievedAt < rhs.achievedAt
    }

    enum CodingKeys: String, CodingKey { case survival = "p", achievedAt = "at" }
}
