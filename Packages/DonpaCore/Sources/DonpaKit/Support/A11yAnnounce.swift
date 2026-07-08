import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Speak a transient message through the running screen reader (VoiceOver).
/// For ephemeral UI — toasts, auto-dismissing banners — whose information would
/// otherwise never reach an a11y user. No-op when no screen reader is running.
@MainActor
enum A11yAnnounce {
    static func post(_ message: String) {
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: message)
        #elseif canImport(AppKit)
        guard let window = NSApp?.mainWindow else { return }
        NSAccessibility.post(
            element: window, notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
        #endif
    }
}
