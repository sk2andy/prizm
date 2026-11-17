import Observation
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Non-secret preferences shared by Settings and the app's lock/sync lifecycle.
@Observable
@MainActor
final class AppPreferences {
    private let defaults: UserDefaults

    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }
    var autoLockMinutes: Int {
        didSet {
            let clamped = min(max(autoLockMinutes, 0), 1440)
            if autoLockMinutes != clamped { autoLockMinutes = clamped; return }
            defaults.set(autoLockMinutes, forKey: Key.autoLockMinutes)
        }
    }
    var lockOnMacLock: Bool {
        didSet { defaults.set(lockOnMacLock, forKey: Key.lockOnMacLock) }
    }
    var lockOnSleep: Bool {
        didSet { defaults.set(lockOnSleep, forKey: Key.lockOnSleep) }
    }
    var lockOnScreenSaver: Bool {
        didSet { defaults.set(lockOnScreenSaver, forKey: Key.lockOnScreenSaver) }
    }
    var dailyLockEnabled: Bool {
        didSet { defaults.set(dailyLockEnabled, forKey: Key.dailyLockEnabled) }
    }
    var dailyLockHour: Int {
        didSet {
            let clamped = min(max(dailyLockHour, 0), 23)
            if dailyLockHour != clamped { dailyLockHour = clamped; return }
            defaults.set(dailyLockHour, forKey: Key.dailyLockHour)
        }
    }
    var dailyLockMinute: Int {
        didSet {
            let clamped = min(max(dailyLockMinute, 0), 59)
            if dailyLockMinute != clamped { dailyLockMinute = clamped; return }
            defaults.set(dailyLockMinute, forKey: Key.dailyLockMinute)
        }
    }
    var syncIntervalMinutes: Int {
        didSet {
            let clamped = min(max(syncIntervalMinutes, 0), 1440)
            if syncIntervalMinutes != clamped { syncIntervalMinutes = clamped; return }
            defaults.set(syncIntervalMinutes, forKey: Key.syncIntervalMinutes)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = AppAppearance(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        autoLockMinutes = min(max(defaults.integer(forKey: Key.autoLockMinutes), 0), 1440)
        lockOnMacLock = defaults.object(forKey: Key.lockOnMacLock) as? Bool ?? true
        lockOnSleep = defaults.object(forKey: Key.lockOnSleep) as? Bool ?? true
        lockOnScreenSaver = defaults.object(forKey: Key.lockOnScreenSaver) as? Bool ?? true
        dailyLockEnabled = defaults.bool(forKey: Key.dailyLockEnabled)
        dailyLockHour = min(max(defaults.object(forKey: Key.dailyLockHour) as? Int ?? 18, 0), 23)
        dailyLockMinute = min(max(defaults.integer(forKey: Key.dailyLockMinute), 0), 59)
        syncIntervalMinutes = min(max(defaults.integer(forKey: Key.syncIntervalMinutes), 0), 1440)
    }

    // macOS 15: avoid the isolated-deinit crash (swiftlang/swift#88036).
    nonisolated deinit {}

    private enum Key {
        static let appearance = "appearance"
        static let autoLockMinutes = "autoLockMinutes"
        static let lockOnMacLock = "lockOnMacLock"
        static let lockOnSleep = "lockOnSleep"
        static let lockOnScreenSaver = "lockOnScreenSaver"
        static let dailyLockEnabled = "dailyLockEnabled"
        static let dailyLockHour = "dailyLockHour"
        static let dailyLockMinute = "dailyLockMinute"
        static let syncIntervalMinutes = "syncIntervalMinutes"
    }
}
