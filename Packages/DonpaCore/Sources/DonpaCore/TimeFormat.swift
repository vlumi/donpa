import Foundation

/// Formats centiseconds as `m:ss.t`, rolling into `h:mm:ss.t` past an hour,
/// TRUNCATED to the tenth — the in-game timer truncates to whole seconds, and
/// rounding here let a clock reading "49" record as "50.0" (49.95s rounded).
public enum TimeFormat {
    public static func mmsst(centiseconds: Int) -> String {
        let tenths = centiseconds / 10
        let totalSeconds = tenths / 10
        let frac = tenths % 10
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%d", hours, minutes, seconds, frac)
        }
        return String(format: "%d:%02d.%d", minutes, seconds, frac)
    }

    /// The improvement AS DISPLAYED: delta of truncated tenths (in centiseconds,
    /// for the shared formatter), nil when the shown value didn't visibly change —
    /// a raw-centisecond delta can contradict the screen (18.24s → 18.15s reads
    /// "0.0s" while the shown best went 18.2 → 18.1).
    public static func displayedImprovement(from prior: Int, to new: Int) -> Int? {
        let deltaTenths = prior / 10 - new / 10
        return deltaTenths > 0 ? deltaTenths * 10 : nil
    }
}
