import DonpaCore
import Foundation

/// Shared number/duration formatting for the scoreboard — an extension so it
/// doesn't count against `ScoreboardView`'s type-body-length budget.
extension ScoreboardView {
    /// A count with the locale's grouping separator (e.g. `1,234,567`).
    static func grouped(_ value: Int) -> String { value.formatted(.number) }

    /// Coarse lifetime-playtime duration: `14h 23m`, `45m`, `< 1m`.
    static func durationLabel(_ centiseconds: Int) -> String {
        let totalMinutes = centiseconds / 6000
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 {
            return String(
                localized: "\(h)h \(m)m", bundle: .module,
                comment: "Playtime, hours+minutes: H hours M minutes")
        }
        if m > 0 {
            return String(
                localized: "\(m)m", bundle: .module, comment: "Playtime, minutes only: M minutes")
        }
        return String(
            localized: "< 1m", bundle: .module, comment: "Playtime under a minute")
    }
}
