import Foundation

/// Formats a play time (centiseconds) as `m:ss.t`, TRUNCATED to the tenth — never
/// rounded up. The in-game timer truncates to whole seconds, so rounding here made
/// the two disagree: a clock reading "49" could record as "50.0" (49.95s rounded).
/// Truncating at every precision keeps all time displays consistent downward.
public enum TimeFormat {
    public static func mmsst(centiseconds: Int) -> String {
        let tenths = centiseconds / 10  // truncate centiseconds → tenths
        let totalSeconds = tenths / 10
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let frac = tenths % 10
        return String(format: "%d:%02d.%d", minutes, seconds, frac)
    }

    /// The improvement between two times AS DISPLAYED: the difference of their
    /// truncated tenths, returned in centiseconds for the shared formatter — or nil
    /// when the displayed value didn't visibly change. A raw-centisecond delta can
    /// contradict the screen (18.24s → 18.15s is a real 9cs improvement but reads
    /// "improved by 0.0s" while the shown best went 18.2 → 18.1, i.e. 0.1).
    public static func displayedImprovement(from prior: Int, to new: Int) -> Int? {
        let deltaTenths = prior / 10 - new / 10
        return deltaTenths > 0 ? deltaTenths * 10 : nil
    }
}
