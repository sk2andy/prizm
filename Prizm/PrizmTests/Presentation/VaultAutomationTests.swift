import XCTest
@testable import Prizm

@MainActor
final class VaultAutomationTests: XCTestCase {
    private var preferences: AppPreferences!
    private var defaults: UserDefaults!
    private var suite: String!
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        suite = "VaultAutomationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        preferences = AppPreferences(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testIdleLock_resetsOnActivity() {
        preferences.autoLockMinutes = 5
        var automation = VaultAutomation(now: start)
        XCTAssertNil(automation.check(at: start.addingTimeInterval(299), preferences: preferences))
        automation.recordActivity(at: start.addingTimeInterval(299))
        XCTAssertNil(automation.check(at: start.addingTimeInterval(301), preferences: preferences))
        XCTAssertEqual(automation.check(at: start.addingTimeInterval(599), preferences: preferences), .lock)
    }

    func testDisabledTimeout_doesNotLockOrSync() {
        var automation = VaultAutomation(now: start)
        XCTAssertNil(automation.check(at: start.addingTimeInterval(86400), preferences: preferences))
    }

    func testDailyLock_firesWhenClockCrossesConfiguredTime_onlyOnce() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = calendar.startOfDay(for: start)
        preferences.dailyLockEnabled = true
        preferences.dailyLockHour = 18
        preferences.dailyLockMinute = 30
        var automation = VaultAutomation(now: morning)
        XCTAssertNil(automation.check(at: morning.addingTimeInterval(18 * 3600), preferences: preferences, calendar: calendar))
        XCTAssertEqual(automation.check(at: morning.addingTimeInterval(19 * 3600), preferences: preferences, calendar: calendar), .lock)
        XCTAssertNil(automation.check(at: morning.addingTimeInterval(19 * 3600 + 1), preferences: preferences, calendar: calendar))
    }

    func testUnlockAfterDailyTime_waitsUntilNextDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let evening = calendar.startOfDay(for: start).addingTimeInterval(20 * 3600)
        preferences.dailyLockEnabled = true
        preferences.dailyLockHour = 18
        var automation = VaultAutomation(now: evening)
        XCTAssertNil(automation.check(at: evening.addingTimeInterval(60), preferences: preferences, calendar: calendar))
        XCTAssertEqual(automation.check(at: evening.addingTimeInterval(23 * 3600), preferences: preferences, calendar: calendar), .lock)
    }

    func testSyncInterval_restartsAfterManualAttempt() {
        preferences.syncIntervalMinutes = 5
        var automation = VaultAutomation(now: start)
        XCTAssertNil(automation.check(at: start.addingTimeInterval(299), preferences: preferences))
        automation.recordSync(at: start.addingTimeInterval(299))
        XCTAssertNil(automation.check(at: start.addingTimeInterval(301), preferences: preferences))
        XCTAssertEqual(automation.check(at: start.addingTimeInterval(599), preferences: preferences), .sync)
    }

    func testLockTakesPriorityOverSync() {
        preferences.autoLockMinutes = 5
        preferences.syncIntervalMinutes = 5
        var automation = VaultAutomation(now: start)
        XCTAssertEqual(automation.check(at: start.addingTimeInterval(300), preferences: preferences), .lock)
    }
}
