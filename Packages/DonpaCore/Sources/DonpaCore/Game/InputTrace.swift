import Foundation
import os

/// Input-path tracing for tap-responsiveness investigations: emits timestamped
/// unified-log lines for the compute gate, the input entry points, and the result
/// panel, so a "board ignores taps" window can be attributed to the subsystem that
/// actually ate the taps (gate vs overlay vs never-reached-the-scene).
///
/// Off unless launched with `-donpa.inputtrace` (zero cost otherwise). Capture with
///   xcrun simctl spawn <udid> log stream --predicate 'category == "inputtrace"'
public enum InputTrace {
    public static let enabled =
        ProcessInfo.processInfo.arguments.contains("-donpa.inputtrace")

    private static let logger = Logger(subsystem: "fi.misaki.donpa", category: "inputtrace")

    /// Log one trace line. The message is only built when tracing is on.
    /// `.notice`, not `.info`: notice is the default unified-log level, so lines
    /// show in a plain `log stream` AND persist in the log archive — meaning a
    /// device reproduction can be captured with `log collect` after the fact.
    public static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let line = message()
        logger.notice("\(line, privacy: .public)")
    }
}
