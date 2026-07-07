import Foundation

/// The longest-odds forced guess this device has SURVIVED (+ when) — lower
/// survival is luckier. Device-owned like `BestTime`: each device keeps its own,
/// and the cross-device view is projected at merge time by taking the min, so the
/// timestamp always travels with its value. This record is also what makes the
/// later guess-odds achievements retroactive: "survived a ≤1/3" stays answerable
/// from stats alone.
public struct LuckiestGuess: Equatable, Sendable, Codable, Comparable {
    /// Survival probability of the guess at click time, 0...1 (lower = luckier).
    public var survival: Double
    /// When it was survived (wall-clock at record time; labeling, not ordering).
    public var achievedAt: Date

    public init(survival: Double, achievedAt: Date) {
        self.survival = survival
        self.achievedAt = achievedAt
    }

    /// Luckier (lower survival) sorts first; equal odds tie-break to the EARLIER
    /// achievement so the merge projection is deterministic.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.survival != rhs.survival { return lhs.survival < rhs.survival }
        return lhs.achievedAt < rhs.achievedAt
    }

    enum CodingKeys: String, CodingKey { case survival = "p", achievedAt = "at" }
}
