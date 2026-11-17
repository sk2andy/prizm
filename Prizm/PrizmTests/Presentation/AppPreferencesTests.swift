import SwiftUI
import XCTest
@testable import Prizm

@MainActor
final class AppPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func testDefaults_preserveExistingLockBehaviorWithoutStartingTimers() {
        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(preferences.appearance, .system)
        XCTAssertNil(preferences.appearance.colorScheme)
        XCTAssertEqual(preferences.autoLockMinutes, 0)
        XCTAssertEqual(preferences.syncIntervalMinutes, 0)
        XCTAssertTrue(preferences.lockOnMacLock)
        XCTAssertTrue(preferences.lockOnSleep)
        XCTAssertTrue(preferences.lockOnScreenSaver)
        XCTAssertFalse(preferences.dailyLockEnabled)
        XCTAssertEqual(preferences.dailyLockHour, 18)
        XCTAssertEqual(preferences.dailyLockMinute, 0)
        XCTAssertTrue((defaults.persistentDomain(forName: suiteName) ?? [:]).isEmpty)
    }

    func testPreferences_surviveRecreation() {
        let preferences = AppPreferences(defaults: defaults)
        preferences.appearance = .dark
        preferences.autoLockMinutes = 90
        preferences.syncIntervalMinutes = 15
        preferences.lockOnMacLock = false
        preferences.lockOnSleep = false
        preferences.lockOnScreenSaver = false
        preferences.dailyLockEnabled = true
        preferences.dailyLockHour = 21
        preferences.dailyLockMinute = 45

        let restored = AppPreferences(defaults: defaults)
        XCTAssertEqual(restored.appearance, .dark)
        XCTAssertEqual(restored.appearance.colorScheme, .dark)
        XCTAssertEqual(restored.autoLockMinutes, 90)
        XCTAssertEqual(restored.syncIntervalMinutes, 15)
        XCTAssertFalse(restored.lockOnMacLock)
        XCTAssertFalse(restored.lockOnSleep)
        XCTAssertFalse(restored.lockOnScreenSaver)
        XCTAssertTrue(restored.dailyLockEnabled)
        XCTAssertEqual(restored.dailyLockHour, 21)
        XCTAssertEqual(restored.dailyLockMinute, 45)
    }

    func testDurationAndTimeValues_stayWithinSupportedRanges() {
        let preferences = AppPreferences(defaults: defaults)
        preferences.autoLockMinutes = -5
        preferences.syncIntervalMinutes = 10000
        preferences.dailyLockHour = 35
        preferences.dailyLockMinute = -1

        XCTAssertEqual(preferences.autoLockMinutes, 0)
        XCTAssertEqual(preferences.syncIntervalMinutes, 1440)
        XCTAssertEqual(preferences.dailyLockHour, 23)
        XCTAssertEqual(preferences.dailyLockMinute, 0)
        let restored = AppPreferences(defaults: defaults)
        XCTAssertEqual(restored.syncIntervalMinutes, 1440)
        XCTAssertEqual(restored.dailyLockHour, 23)
    }

    func testAppearance_explicitLightOverridesSystem() {
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
        XCTAssertNil(AppAppearance.system.colorScheme)
    }
}
