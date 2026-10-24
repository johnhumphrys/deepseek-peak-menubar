import Foundation

/// User-facing options persisted in UserDefaults.
public enum PreferencesKey {
    public static let leadTimeMinutes = "leadTimeMinutes"
    public static let menuBarContent = "menuBarContent"
    public static let launchAtLogin = "launchAtLogin"
}

public enum MenuBarContent: String, CaseIterable, Sendable {
    case dotOnly
    case stateOnly
    case stateAndCountdown

    public var title: String {
        switch self {
        case .dotOnly: return "Dot only"
        case .stateOnly: return "State"
        case .stateAndCountdown: return "State + countdown"
        }
    }
}

public struct Preferences {
    public static let defaultLeadTimeMinutes = 30
    public static let defaultMenuBarContent = MenuBarContent.stateAndCountdown
    public static let leadTimeChoices = [10, 15, 30, 60, 120]

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var leadTimeMinutes: Int {
        get {
            let stored = defaults.integer(forKey: PreferencesKey.leadTimeMinutes)
            return stored > 0 ? stored : Self.defaultLeadTimeMinutes
        }
        nonmutating set {
            defaults.set(max(1, newValue), forKey: PreferencesKey.leadTimeMinutes)
        }
    }

    public var leadTime: TimeInterval { TimeInterval(leadTimeMinutes * 60) }

    public var menuBarContent: MenuBarContent {
        get {
            guard let raw = defaults.string(forKey: PreferencesKey.menuBarContent),
                  let value = MenuBarContent(rawValue: raw)
            else { return Self.defaultMenuBarContent }
            return value
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: PreferencesKey.menuBarContent)
        }
    }
}
