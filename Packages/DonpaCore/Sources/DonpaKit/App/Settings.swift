import DonpaCore
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

/// Persisted user settings (appearance + last board selection), backed by
/// `UserDefaults`, so the picker restores the player's last choice across launches.
@MainActor
public final class Settings: ObservableObject {
    let defaults: UserDefaults

    @Stored("donpa.appearance") public var appearance: AppearancePreference = .system
    /// The board family whose page the New Game picker shows (and starts from).
    @Stored("donpa.family") public var family: BoardFamily = .practice
    // Grid and Hive remember their OWN size/density/edges independently — picking
    // a huge Round hive must not retune the next Grid game.
    @Stored("donpa.grid.size") public var gridSize: BoardSize = .s
    @Stored("donpa.grid.density") public var gridDensity: Density = .normal
    @Stored("donpa.grid.edges") public var gridEdges: BoardEdges = .flat
    @Stored("donpa.hive.size") public var hiveSize: BoardSize = .s
    @Stored("donpa.hive.density") public var hiveDensity: Density = .normal
    @Stored("donpa.hive.edges") public var hiveEdges: BoardEdges = .flat
    @Stored("donpa.classicPreset") public var basicPreset: BasicPreset = .beginner
    /// Drills' own remembered size (its only axis — density is fixed).
    @Stored("donpa.practice.size") public var practiceSize: BoardSize = .s

    /// The display name last used when sharing scores — remembered so the share
    /// sheet pre-fills it. The local defaults copy is a CACHE; the durable home is
    /// the synchronizable Keychain beside the signing key (via `shareNameStore`),
    /// so the name half of the identity follows the key across devices.
    @Published public var shareName: String {
        didSet {
            defaults.set(shareName, forKey: Self.shareNameKey)
            shareNameStore?.sharedName = shareName
        }
    }

    /// Whether shares include career totals — sticky per device.
    @Stored("donpa.shareIncludeCareer") public var shareIncludeCareer = false

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

    @Stored("donpa.handedness") public var handedness: Handedness = .left
    /// Show the big-board minimap overview (only appears when the board also
    /// exceeds the viewport).
    @Stored("donpa.showMinimap") public var showMinimap = true
    /// The Record's Decorations block, folded away.
    @Stored("donpa.medalsCollapsed") public var medalsCollapsed = false
    /// Minimap size multiplier over its base size; the scene clamps it.
    @Stored("donpa.minimapScale") public var minimapScale = 1.0
    /// Bypass progressive gating: the picker offers everything, no wins needed.
    /// Freely reversible — gates derive from records, so turning this off just
    /// returns to whatever the wins say (including any earned while it was on).
    /// DEVICE-scoped like the other toggles (the records themselves sync).
    @Stored("donpa.unlockAll") public var unlockAll = false
    /// Add a "?" step to the flag cycle (hidden → flag → "?" → clear). Opt-in,
    /// off by default: the third state taxes the common flag→clear tap.
    @Stored("donpa.questionMarks") public var questionMarks = false
    /// The Record's last-browsed Family × Edges filter, so reopening lands
    /// where you left off (an in-game open still seeds to the played board).
    @Stored("donpa.scoreFilterFamily") public var scoreFilterFamily: BoardFamily = .basic
    @Stored("donpa.scoreFilterEdges") public var scoreFilterEdges: BoardEdges = .flat
    /// The marketing version the review prompt last fired for.
    @Stored("donpa.reviewPromptedVersion") public var reviewPromptedVersion = ""
    /// Play sound effects (flag/chord/reveal + the result sting). On by default;
    /// on iOS the Ring/Silent switch also mutes it (the audio session is `.ambient`).
    @Stored("donpa.sound") public var sound = true
    /// Per-move haptics. On by default; iOS-only in effect.
    @Stored("donpa.haptics") public var haptics = true
    /// Sync the scoreboard across devices via iCloud. Opt-in, off by default — our
    /// own toggle, not a system grant (KVS rides on the system sign-in).
    @Stored(Settings.syncScoresKey) public var syncScores = false
    /// Language override. Persisted as our preference and written to
    /// `AppleLanguages` for the system to pick up next launch.
    @Published public var language: LanguagePreference {
        didSet {
            defaults.set(language.rawValue, forKey: Self.languageKey)
            if let code = language.languageCode {
                defaults.set([code], forKey: "AppleLanguages")
            } else {
                defaults.removeObject(forKey: "AppleLanguages")
            }
        }
    }

    /// Read raw at app init, before a Settings exists (the store wiring needs it).
    public static let syncScoresKey = "donpa.syncScores"
    private static let shareNameKey = "donpa.shareName"
    private static let languageKey = "donpa.language"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shareName = defaults.string(forKey: Self.shareNameKey) ?? ""
        language =
            defaults.string(forKey: Self.languageKey).flatMap(LanguagePreference.init(rawValue:))
            ?? .system
        Self.migrateLegacySelections(in: defaults)
    }

    /// Pre-family installs stored mode/shape + one SHARED size/density/edges set;
    /// Drills guards against a smuggled off-ladder size. Writes each family key
    /// only when absent, so it runs idempotently before `@Stored`'s first read.
    private static func migrateLegacySelections(in defaults: UserDefaults) {
        func write(_ raw: String?, to key: String) {
            guard defaults.string(forKey: key) == nil, let raw else { return }
            defaults.set(raw, forKey: key)
        }
        if let mode = defaults.string(forKey: "donpa.mode") {
            write(
                legacyFamily(mode: mode, shape: defaults.string(forKey: "donpa.modernShape"))
                    .rawValue,
                to: "donpa.family")
        }
        let sharedSize = defaults.string(forKey: "donpa.modernSize")
        let sharedDensity = defaults.string(forKey: "donpa.modernDensity")
        let sharedEdges = defaults.string(forKey: "donpa.modernEdges")
            .flatMap(edgesValue(from:))?.rawValue
        for family in ["grid", "hive"] {
            write(sharedSize, to: "donpa.\(family).size")
            write(sharedDensity, to: "donpa.\(family).density")
            write(sharedEdges, to: "donpa.\(family).edges")
        }
        // Own edges keys may also hold the legacy vocabulary from older builds.
        for key in ["donpa.grid.edges", "donpa.hive.edges"] {
            if let raw = defaults.string(forKey: key), BoardEdges(rawValue: raw) == nil {
                defaults.set(edgesValue(from: raw)?.rawValue, forKey: key)
            }
        }
        if let raw = defaults.string(forKey: "donpa.practice.size"),
            let size = BoardSize(rawValue: raw),
            !GameConfig.practiceSizes.contains(size)
        {
            defaults.removeObject(forKey: "donpa.practice.size")
        }
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
    /// later plain New Game / relaunch remembers this board.
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

extension AppearancePreference: DefaultsValue {}
extension BoardFamily: DefaultsValue {}
extension BoardSize: DefaultsValue {}
extension Density: DefaultsValue {}
extension BoardEdges: DefaultsValue {}
extension BasicPreset: DefaultsValue {}
extension Handedness: DefaultsValue {}
extension LanguagePreference: DefaultsValue {}
