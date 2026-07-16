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

    /// The signed difference of two times AS DISPLAYED: each truncated to its
    /// tenth before subtracting, so the result can never contradict the two
    /// times on screen (hidden centisecond precision would read as a rounding
    /// error). Result is in centiseconds — always a whole-tenth multiple — for
    /// the shared formatter. `b - a`, so a faster `b` is negative.
    ///
    /// The one rule for every displayed time comparison — record banners,
    /// rival gaps, and anywhere else two shown times are diffed.
    public static func displayedDelta(_ a: Int, _ b: Int) -> Int {
        (b / 10 - a / 10) * 10
    }

    /// The improvement AS DISPLAYED (positive centiseconds), nil when the shown
    /// value didn't visibly change — 18.24 → 18.15 shows one tenth faster, but
    /// 18.24 → 18.21 both read 18.2, so no pill.
    public static func displayedImprovement(from prior: Int, to new: Int) -> Int? {
        let delta = displayedDelta(new, prior)  // prior − new: positive = faster
        return delta > 0 ? delta : nil
    }

    /// A signed displayed gap as `±m:ss.t`, from the two raw times. Quantizes to
    /// displayed tenths (so it matches the times on screen), then signs it —
    /// `mine` faster than `theirs` reads negative. Empty for a shown tie.
    public static func signedGap(mine: Int, theirs: Int) -> String {
        let gap = displayedDelta(theirs, mine)  // mine − theirs: negative = faster
        guard gap != 0 else { return "" }
        return (gap < 0 ? "−" : "+") + mmsst(centiseconds: abs(gap))
    }
}
