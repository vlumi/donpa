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
    /// SwiftUI alignment for the floating toggle's corner.
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

/// Persisted user settings (appearance + last board selection), backed by
/// `UserDefaults`, so the picker restores the player's last choice across launches.
@MainActor
public final class Settings: ObservableObject {
    @Published public var appearance: AppearancePreference {
        didSet { defaults.set(appearance.rawValue, forKey: appearanceKey) }
    }
    /// The board family whose page the New Game picker shows (and starts from).
    @Published public var family: BoardFamily {
        didSet { defaults.set(family.rawValue, forKey: familyKey) }
    }
    // Grid and Hive remember their OWN size/density/edges independently — picking
    // a huge Round hive must not retune the next Grid game (user decision).
    @Published public var gridSize: BoardSize {
        didSet { defaults.set(gridSize.rawValue, forKey: "donpa.grid.size") }
    }
    @Published public var gridDensity: Density {
        didSet { defaults.set(gridDensity.rawValue, forKey: "donpa.grid.density") }
    }
    @Published public var gridEdges: BoardEdges {
        didSet { defaults.set(gridEdges.rawValue, forKey: "donpa.grid.edges") }
    }
    @Published public var hiveSize: BoardSize {
        didSet { defaults.set(hiveSize.rawValue, forKey: "donpa.hive.size") }
    }
    @Published public var hiveDensity: Density {
        didSet { defaults.set(hiveDensity.rawValue, forKey: "donpa.hive.density") }
    }
    @Published public var hiveEdges: BoardEdges {
        didSet { defaults.set(hiveEdges.rawValue, forKey: "donpa.hive.edges") }
    }
    @Published public var basicPreset: BasicPreset {
        didSet { defaults.set(basicPreset.rawValue, forKey: presetKey) }
    }
    /// Drills' own remembered size (its only axis — density is fixed).
    @Published public var practiceSize: BoardSize {
        didSet { defaults.set(practiceSize.rawValue, forKey: "donpa.practice.size") }
    }
    /// The display name last used when sharing scores — remembered so the share
    /// sheet pre-fills it. The local defaults copy is a CACHE; the durable home is
    /// the synchronizable Keychain beside the signing key (via `shareNameStore`),
    /// so the name half of the identity follows the key across devices.
    @Published public var shareName: String {
        didSet {
            defaults.set(shareName, forKey: shareNameKey)
            shareNameStore?.sharedName = shareName
        }
    }

    /// Whether shares include career totals — sticky per device, so the choice
    /// survives reopening the share card (it used to reset to off every time).
    @Published public var shareIncludeCareer: Bool {
        didSet { defaults.set(shareIncludeCareer, forKey: shareIncludeCareerKey) }
    }

    /// The Keychain bridge for `shareName`, set by the app at startup (nil in
    /// tests — defaults-only there). Assigning reconciles immediately.
    public var shareNameStore: ShareIdentityStore? {
        didSet { reconcileShareName() }
    }

    /// Adopt the synced name — the Keychain copy wins, it's the latest cross-device
    /// write (an empty synced value is a real "cleared" and clears here too). A
    /// pre-existing local-only name with nothing synced yet is pushed up instead
    /// (the migration for installs that set a name before the name synced).
    public func reconcileShareName() {
        guard let store = shareNameStore else { return }
        if let synced = store.sharedName {
            if synced != shareName { shareName = synced }
        } else if !shareName.isEmpty {
            store.sharedName = shareName
        }
    }

    /// Key paths to a family's own axes, so the picker and keyboard nav bind to
    /// whichever page they're on. Basic has no axes; callers guard on family.
    public static func sizePath(_ family: BoardFamily) -> ReferenceWritableKeyPath<
        Settings, BoardSize
    > {
        switch family {
        case .hive: return \.hiveSize
        case .practice: return \.practiceSize
        default: return \.gridSize
        }
    }
    public static func densityPath(_ family: BoardFamily) -> ReferenceWritableKeyPath<
        Settings, Density
    > {
        family == .hive ? \.hiveDensity : \.gridDensity
    }
    public static func edgesPath(_ family: BoardFamily) -> ReferenceWritableKeyPath<
        Settings, BoardEdges
    > {
        family == .hive ? \.hiveEdges : \.gridEdges
    }
    @Published public var handedness: Handedness {
        didSet { defaults.set(handedness.rawValue, forKey: handednessKey) }
    }
    /// Show the big-board minimap overview (only appears when the board also
    /// exceeds the viewport).
    @Published public var showMinimap: Bool {
        didSet { defaults.set(showMinimap, forKey: showMinimapKey) }
    }
    /// Minimap size multiplier over its base size, persisted so a resize survives
    /// new game / restart / save-restore. The scene clamps it to a sane range.
    @Published public var minimapScale: Double {
        didSet { defaults.set(minimapScale, forKey: minimapScaleKey) }
    }
    /// Add a "?" step to the flag cycle (hidden → flag → "?" → clear). Opt-in, off
    /// by default: the third state taxes the common flag→clear tap, so only players
    /// who want the classic maybe-mark pay for it.
    @Published public var questionMarks: Bool {
        didSet { defaults.set(questionMarks, forKey: questionMarksKey) }
    }
    /// Play sound effects (flag/chord/reveal + the result sting). On by default;
    /// on iOS the Ring/Silent switch also mutes it (the audio session is `.ambient`).
    @Published public var sound: Bool {
        didSet { defaults.set(sound, forKey: soundKey) }
    }
    /// Per-move haptics (flag tick, chord thud, dig rumble). On by default; iOS-only
    /// in effect (no-op where there's no Taptic Engine).
    @Published public var haptics: Bool {
        didSet { defaults.set(haptics, forKey: hapticsKey) }
    }
    /// Sync the scoreboard across devices via iCloud. Opt-in, off by default — our
    /// own toggle, not a system grant (KVS rides on the system sign-in).
    @Published public var syncScores: Bool {
        didSet { defaults.set(syncScores, forKey: syncScoresKey) }
    }
    /// Language override. Persisted as our preference and written to
    /// `AppleLanguages` for the system to pick up next launch.
    @Published public var language: LanguagePreference {
        didSet {
            defaults.set(language.rawValue, forKey: languageKey)
            if let code = language.languageCode {
                defaults.set([code], forKey: "AppleLanguages")
            } else {
                defaults.removeObject(forKey: "AppleLanguages")
            }
        }
    }

    private let defaults: UserDefaults
    private let appearanceKey = "donpa.appearance"
    private let familyKey = "donpa.family"
    private let presetKey = "donpa.classicPreset"
    private let shareNameKey = "donpa.shareName"
    private let shareIncludeCareerKey = "donpa.shareIncludeCareer"
    // Legacy (pre-family / pre-split) selection keys, read once for migration:
    // mode+shape became the family; the shared size/density/edges seed BOTH
    // families' own axes.
    private let legacyModeKey = "donpa.mode"
    private let legacyShapeKey = "donpa.modernShape"
    private let legacySizeKey = "donpa.modernSize"
    private let legacyDensityKey = "donpa.modernDensity"
    private let legacyEdgesKey = "donpa.modernEdges"
    private let handednessKey = "donpa.handedness"
    private let languageKey = "donpa.language"
    private let showMinimapKey = "donpa.showMinimap"
    private let minimapScaleKey = "donpa.minimapScale"
    private let questionMarksKey = "donpa.questionMarks"
    private let soundKey = "donpa.sound"
    private let hapticsKey = "donpa.haptics"
    private let syncScoresKey = "donpa.syncScores"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance =
            defaults.string(forKey: appearanceKey).flatMap(AppearancePreference.init(rawValue:))
            ?? .system
        // Family: prefer the stored value; else migrate a pre-family install's
        // mode+shape selection (classic → basic; modern → grid/hive by shape).
        // A GENUINELY fresh install — no family key AND no legacy mode key — lands
        // on Drills, the no-guess on-ramp (a newcomer learns the patterns before
        // the real families). A pre-family veteran has the legacy key, so they
        // migrate to their old pick and are never yanked to Drills.
        let legacyMode = defaults.string(forKey: legacyModeKey)
        family =
            defaults.string(forKey: familyKey).flatMap(BoardFamily.init(rawValue:))
            ?? (legacyMode == nil
                ? .practice
                : Self.legacyFamily(
                    mode: legacyMode, shape: defaults.string(forKey: legacyShapeKey)))
        // Per-family axes: prefer each family's own stored value; fall back to the
        // legacy SHARED keys (seeding both families with the old pick), then the
        // defaults. Legacy edges values used the bounded/wrapped vocabulary.
        let sharedSize =
            defaults.string(forKey: legacySizeKey).flatMap(BoardSize.init(rawValue:)) ?? .s
        let sharedDensity =
            defaults.string(forKey: legacyDensityKey).flatMap(Density.init(rawValue:)) ?? .normal
        let sharedEdges =
            defaults.string(forKey: legacyEdgesKey).flatMap(Self.edgesValue(from:)) ?? .flat
        func axis<T>(_ key: String, _ parse: (String) -> T?, else shared: T) -> T {
            defaults.string(forKey: key).flatMap(parse) ?? shared
        }
        gridSize = axis("donpa.grid.size", BoardSize.init(rawValue:), else: sharedSize)
        gridDensity = axis("donpa.grid.density", Density.init(rawValue:), else: sharedDensity)
        gridEdges = axis("donpa.grid.edges", Self.edgesValue(from:), else: sharedEdges)
        hiveSize = axis("donpa.hive.size", BoardSize.init(rawValue:), else: sharedSize)
        hiveDensity = axis("donpa.hive.density", Density.init(rawValue:), else: sharedDensity)
        hiveEdges = axis("donpa.hive.edges", Self.edgesValue(from:), else: sharedEdges)
        // Drills is post-legacy, so no shared-key seeding — default S, like the
        // other families' size axes. Clamped to ITS ladder: a stored huge size
        // (tampered or from a future build) must not smuggle an un-generatable
        // board into the no-guess mode.
        let storedPractice = axis("donpa.practice.size", BoardSize.init(rawValue:), else: .s)
        practiceSize = GameConfig.practiceSizes.contains(storedPractice) ? storedPractice : .s
        basicPreset =
            defaults.string(forKey: presetKey).flatMap(BasicPreset.init(rawValue:)) ?? .beginner
        shareName = defaults.string(forKey: shareNameKey) ?? ""
        shareIncludeCareer = defaults.object(forKey: shareIncludeCareerKey) as? Bool ?? false
        handedness =
            defaults.string(forKey: handednessKey).flatMap(Handedness.init(rawValue:)) ?? .left
        // Default ON: check presence explicitly, since `bool(forKey:)` is false when
        // the key is missing.
        showMinimap = defaults.object(forKey: showMinimapKey) as? Bool ?? true
        // Default 1.0 (base size); a stored value restores the player's last size.
        minimapScale = defaults.object(forKey: minimapScaleKey) as? Double ?? 1.0
        // Off by default — the "?" step is opt-in.
        questionMarks = defaults.object(forKey: questionMarksKey) as? Bool ?? false
        // On by default — the ringer switch is the quick mute on iOS.
        sound = defaults.object(forKey: soundKey) as? Bool ?? true
        haptics = defaults.object(forKey: hapticsKey) as? Bool ?? true
        syncScores = defaults.object(forKey: syncScoresKey) as? Bool ?? false
        language =
            defaults.string(forKey: languageKey).flatMap(LanguagePreference.init(rawValue:))
            ?? .system
    }

    /// The `GameConfig` implied by the current family + ITS selections. All
    /// family × edges combinations are supported (every Grid/Hive size is
    /// even-sided, so the Round hive torus is valid).
    public var currentConfig: GameConfig {
        switch family {
        case .basic: return .basic(basicPreset)
        case .grid: return .grid(gridSize, gridDensity, gridEdges)
        case .hive: return .hive(hiveSize, hiveDensity, hiveEdges)
        case .practice: return .practice(practiceSize)
        }
    }

    /// Adopt a `GameConfig` as the current selection — sets the family and its
    /// per-family size/density/edges so `currentConfig` round-trips to it, and so a
    /// later plain New Game / relaunch remembers this board. Used when a game is
    /// started from a specific config (e.g. the scoreboard's "New game on this
    /// board") rather than by editing the picker.
    public func adopt(_ config: GameConfig) {
        family = config.family
        switch config {
        case .basic(let preset):
            basicPreset = preset
        case .grid(let size, let density, let edges):
            gridSize = size
            gridDensity = density
            gridEdges = edges
        case .hive(let size, let density, let edges):
            hiveSize = size
            hiveDensity = density
            hiveEdges = edges
        case .practice(let size):
            practiceSize = size
        }
    }

    /// Map a pre-family install's stored mode/shape selection onto a family.
    private static func legacyFamily(mode: String?, shape: String?) -> BoardFamily {
        guard mode == "modern" else { return .basic }
        return shape == "hex" ? .hive : .grid
    }

    /// Decode an edges raw value, accepting the legacy bounded/wrapped vocabulary.
    private static func edgesValue(from raw: String) -> BoardEdges? {
        switch raw {
        case "bounded": return .flat
        case "wrapped": return .round
        default: return BoardEdges(rawValue: raw)
        }
    }
}
