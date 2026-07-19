import DonpaCore
import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#endif

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

// MARK: - Sheet sizing (macOS bounds the Record to the presenting window)

extension ScoreboardView {
    var macSheetWidth: CGFloat? {
        #if os(macOS)
        sheetWidth
        #else
        nil
        #endif
    }
    var macSheetHeight: CGFloat? {
        #if os(macOS)
        sheetHeight
        #else
        nil
        #endif
    }

    #if os(macOS)
    /// Container to bound against: the presenting window, or the screen as a
    /// fallback before its size is known.
    var container: CGSize {
        if available != .zero { return available }
        let h = NSScreen.main?.visibleFrame.height ?? 800
        let w = NSScreen.main?.visibleFrame.width ?? 1000
        return CGSize(width: w, height: h)
    }

    /// Tall in a big window, short in a small one, bounded so it never overflows.
    var sheetHeight: CGFloat { min(1100, max(380, container.height * 0.94)) }
    /// Cap past the two-column breakpoint so a roomy window gives two columns; a
    /// small window still shrinks to fit.
    var sheetWidth: CGFloat { min(820, max(300, container.width * 0.9)) }
    #endif
}
