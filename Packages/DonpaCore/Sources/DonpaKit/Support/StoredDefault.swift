import Foundation

/// A value `@Stored` can persist in `UserDefaults`.
public protocol DefaultsValue {
    static func load(from defaults: UserDefaults, key: String) -> Self?
    func store(in defaults: UserDefaults, key: String)
}

extension Bool: DefaultsValue {
    public static func load(from defaults: UserDefaults, key: String) -> Bool? {
        defaults.object(forKey: key) as? Bool
    }
    public func store(in defaults: UserDefaults, key: String) { defaults.set(self, forKey: key) }
}

extension Double: DefaultsValue {
    public static func load(from defaults: UserDefaults, key: String) -> Double? {
        defaults.object(forKey: key) as? Double
    }
    public func store(in defaults: UserDefaults, key: String) { defaults.set(self, forKey: key) }
}

extension String: DefaultsValue {
    public static func load(from defaults: UserDefaults, key: String) -> String? {
        defaults.string(forKey: key)
    }
    public func store(in defaults: UserDefaults, key: String) { defaults.set(self, forKey: key) }
}

extension DefaultsValue where Self: RawRepresentable, RawValue == String {
    public static func load(from defaults: UserDefaults, key: String) -> Self? {
        defaults.string(forKey: key).flatMap(Self.init(rawValue:))
    }
    public func store(in defaults: UserDefaults, key: String) {
        defaults.set(rawValue, forKey: key)
    }
}

/// One persisted `Settings` preference: reads through to the instance's
/// `UserDefaults`, writes back on set, and emits `objectWillChange` — a
/// one-line replacement for the @Published + didSet + key + init-read
/// quartet. Preferences needing migration write their migrated value into
/// defaults in `Settings.init` BEFORE first read; ones with side effects
/// beyond persistence (shareName, language) stay hand-rolled.
@propertyWrapper
public struct Stored<Value: DefaultsValue> {
    private let key: String
    private let fallback: Value

    public init(wrappedValue: Value, _ key: String) {
        self.key = key
        self.fallback = wrappedValue
    }

    @MainActor
    public static subscript(
        _enclosingInstance instance: Settings,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<Settings, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<Settings, Self>
    ) -> Value {
        get {
            let box = instance[keyPath: storageKeyPath]
            return Value.load(from: instance.defaults, key: box.key) ?? box.fallback
        }
        set {
            instance.objectWillChange.send()
            newValue.store(in: instance.defaults, key: instance[keyPath: storageKeyPath].key)
        }
    }

    @available(*, unavailable, message: "@Stored lives on Settings only")
    public var wrappedValue: Value {
        get { fatalError() }
        // swiftlint:disable:next unused_setter_value
        set { fatalError() }
    }
}
