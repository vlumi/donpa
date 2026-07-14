import Foundation

/// A grow-only counter (G-Counter). Invariant: a device only ever writes its
/// OWN `mine`, never merging another's — `othersTotal` is a cached sum of every
/// other device's count, refreshed by sync (0 with no sync), so the displayed
/// total is conflict-free.
public struct DeviceCounter: Codable, Equatable, Sendable {
    public private(set) var mine: Int
    public private(set) var othersTotal: Int

    public init(mine: Int = 0, othersTotal: Int = 0) {
        self.mine = mine
        self.othersTotal = othersTotal
    }

    enum CodingKeys: String, CodingKey { case mine, othersTotal }

    /// Fields default to 0 if absent, so an older counter still decodes.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mine = try c.decodeIfPresent(Int.self, forKey: .mine) ?? 0
        othersTotal = try c.decodeIfPresent(Int.self, forKey: .othersTotal) ?? 0
    }

    public var total: Int { mine + othersTotal }

    public mutating func add(_ delta: Int) {
        mine += delta
    }

    public mutating func setOthersTotal(_ sum: Int) {
        othersTotal = sum
    }
}
