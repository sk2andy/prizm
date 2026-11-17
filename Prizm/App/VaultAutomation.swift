import Foundation

/// Scheduling uses supplied dates so idle, daily lock and sync can be checked without real timers.
@MainActor
struct VaultAutomation {
    enum Action: Equatable { case lock, sync }

    private var lastActivity: Date
    private var lastCheck: Date
    private var lastSync: Date

    init(now: Date) {
        lastActivity = now
        lastCheck = now
        lastSync = now
    }

    mutating func recordActivity(at date: Date) { lastActivity = date }
    mutating func recordSync(at date: Date) { lastSync = date }

    mutating func check(at now: Date, preferences: AppPreferences,
                        calendar: Calendar = .current) -> Action? {
        defer { lastCheck = now }
        if preferences.autoLockMinutes > 0,
           now.timeIntervalSince(lastActivity) >= Double(preferences.autoLockMinutes) * 60 {
            return .lock
        }
        if preferences.dailyLockEnabled,
           let nextLock = calendar.nextDate(
               after: lastCheck,
               matching: DateComponents(hour: preferences.dailyLockHour, minute: preferences.dailyLockMinute),
               matchingPolicy: .nextTime), nextLock <= now {
            return .lock
        }
        if preferences.syncIntervalMinutes > 0,
           now.timeIntervalSince(lastSync) >= Double(preferences.syncIntervalMinutes) * 60 {
            return .sync
        }
        return nil
    }
}
