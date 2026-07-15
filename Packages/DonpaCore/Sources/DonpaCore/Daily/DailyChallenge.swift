import Foundation

/// The day's shared board: the LOCAL date string keys everything, so the
/// same calendar date is the same board everywhere (timezones only shift
/// when it flips; a date-changer only cheats themselves). A fixed seed plus
/// a fixed start cell makes first-click-safe placement identical for
/// everyone — the Start reveal always opens the same region, so the board
/// AND the luck are shared.
public enum DailyChallenge {
    /// Day one, PERMANENT (backdated so the calendar opens with history to
    /// explore; backfilled days never feed streaks — only live play does).
    /// The calendar clamps to [epoch, today].
    public static let epochKey = "2026-07-01"

    /// "yyyy-MM-dd" in the user's calendar — the identity of a day.
    public static func dateKey(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The rotation: one-sitting boards, mostly Normal with a spicier
    /// weekend, cycling by the day's position since the epoch. Deterministic
    /// forever — reordering or resizing this table changes every future day.
    static let rotation: [GameConfig] = [
        .grid(.s, .normal, .flat),
        .hive(.s, .normal, .flat),
        .grid(.m, .normal, .flat),
        .hive(.s, .hard, .flat),
        .grid(.s, .hard, .flat),
        .hive(.m, .normal, .flat),
        .grid(.m, .brutal, .flat),
    ]

    public struct Board: Equatable, Sendable {
        public let dateKey: String
        public let config: GameConfig
        public let seed: UInt64
        /// The shared Start reveal — first-click-safe placement guarantees a
        /// 0 here, so everyone opens the identical region.
        public let startCell: Coord
    }

    /// The board for a date key, or nil before the epoch (no board existed).
    ///
    /// The seed is scanned forward from the date hash until the pre-armed
    /// layout leaves the start cell's whole neighbourhood mine-free: the
    /// Start reveal then never relocates a mine — relocation draws from a
    /// non-deterministic RNG, which would silently diverge players' boards.
    /// A clear zone also guarantees the 0-opening. (~3 candidates expected;
    /// the bound is unreachable in practice.)
    public static func board(for dateKey: String) -> Board? {
        guard let ordinal = dayOrdinal(of: dateKey), ordinal >= 0 else { return nil }
        let config = rotation[ordinal % rotation.count]
        let startCell = Coord(config.width / 2, config.height / 2)
        let base = fnv1a("donpa.daily." + dateKey)
        for offset in 0..<64 {
            let seed = base &+ UInt64(offset)
            if startZoneIsClear(config: config, seed: seed, startCell: startCell) {
                return Board(dateKey: dateKey, config: config, seed: seed, startCell: startCell)
            }
        }
        return Board(dateKey: dateKey, config: config, seed: base, startCell: startCell)
    }

    static func startZoneIsClear(config: GameConfig, seed: UInt64, startCell: Coord) -> Bool {
        var game = Game(config: config)
        var rng = SeededGenerator(seed: seed)
        game.placeMinesEagerly(using: &rng)
        guard !game.board[startCell].isMine else { return false }
        return game.board.topology.neighbors(of: startCell).allSatisfy {
            !game.board[$0].isMine
        }
    }

    /// Whole days from the epoch to `dateKey` (negative = before day one).
    /// Date-string arithmetic via UTC so the ordinal is calendar-independent.
    public static func dayOrdinal(of dateKey: String) -> Int? {
        guard let day = utcMidnight(dateKey), let epoch = utcMidnight(epochKey) else {
            return nil
        }
        return Int((day.timeIntervalSince(epoch) / 86_400).rounded())
    }

    private static func utcMidnight(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// FNV-1a — a STABLE hash (Swift's `Hasher` is per-process randomized,
    /// which would give every player a different board).
    static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
