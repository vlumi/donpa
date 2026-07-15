import DonpaCore
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

/// User-chosen appearance. `.system` follows the device setting.
public enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return String(localized: "System", bundle: .module)
        case .light: return String(localized: "Light", bundle: .module)
        case .dark: return String(localized: "Dark", bundle: .module)
        }
    }

    /// The scheme to force on the SwiftUI hierarchy, or nil to follow the system.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// The concrete scheme to render with, so the SwiftUI chrome and the
    /// imperatively-coloured SpriteKit scene agree. For `.system` this resolves the
    /// live OS appearance directly.
    public func resolvedScheme(systemFallback: ColorScheme) -> ColorScheme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system:
            // macOS: the ambient `@Environment(\.colorScheme)` is unreliable under
            // a sibling `.preferredColorScheme`, so read AppKit directly. iOS: the
            // ambient value is authoritative once the forced scheme clears.
            #if canImport(AppKit)
            let match = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
            return match == .darkAqua ? .dark : .light
            #else
            return systemFallback
            #endif
        }
    }
}

/// Which bottom corner the floating reveal/flag toggle sits in. Default `.left`:
/// a right-handed player taps with the right hand and reaches the toggle with the
/// left. Switchable in Settings.
public enum Handedness: String, CaseIterable, Identifiable, Sendable {
    // Order = how the segmented picker lays out left→right, so "Left" sits on the
    // left and "Right" on the right (matching the corner each puts the toggle in).
    case left
    case right

    public var id: String { rawValue }
    public var label: String {
        self == .right
            ? String(localized: "Right", bundle: .module)
            : String(localized: "Left", bundle: .module)
    }
    public var alignment: Alignment { self == .right ? .bottomTrailing : .bottomLeading }
}

/// App language override. Applied by writing `AppleLanguages`, which the system
/// reads at launch — so a change takes effect next launch.
public enum LanguagePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case japanese
    case finnish

    public var id: String { rawValue }

    /// The `AppleLanguages` code this forces, or nil to follow the device.
    public var languageCode: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .japanese: return "ja"
        case .finnish: return "fi"
        }
    }

    /// Each language in its own name (plus localized "System").
    public var label: String {
        switch self {
        case .system: return String(localized: "System", bundle: .module)
        case .english: return "English"
        case .japanese: return "日本語"
        case .finnish: return "Suomi"
        }
    }
}
