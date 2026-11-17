import AppKit
import SwiftUI
import XCTest
@testable import Prizm

@MainActor
final class SystemAppearanceTests: XCTestCase {
    func testSystemAppearance_followsAppAppearanceChanges_withoutKeepingLightOverride() async throws {
        let application = NSApplication.shared
        let previous = application.appearance
        defer { application.appearance = previous }
        application.appearance = NSAppearance(named: .darkAqua)
        let system = SystemAppearance(application: application)
        XCTAssertEqual(system.colorScheme, .dark)
        var choice = AppAppearance.light
        XCTAssertEqual(choice.colorScheme ?? system.colorScheme, .light)
        choice = .system
        XCTAssertEqual(choice.colorScheme ?? system.colorScheme, .dark)

        application.appearance = NSAppearance(named: .aqua)
        try await waitFor(.light, in: system)
        XCTAssertEqual(choice.colorScheme ?? system.colorScheme, .light)
        application.appearance = NSAppearance(named: .darkAqua)
        try await waitFor(.dark, in: system)
        XCTAssertEqual(choice.colorScheme ?? system.colorScheme, .dark)
    }

    private func waitFor(_ expected: ColorScheme, in system: SystemAppearance) async throws {
        let deadline = ContinuousClock.now + .seconds(1)
        while system.colorScheme != expected, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(system.colorScheme, expected)
    }
}
