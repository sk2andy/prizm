import XCTest

/// Opt-in captures from the real app. Run against the isolated preview bundle with
/// TEST_RUNNER_PRIZM_SCREENSHOTS=1; fixture accounts must never share the user's Keychain.
final class RedesignScreenshotTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PRIZM_SCREENSHOTS"] == "1",
                          "Screenshot captures require the isolated preview build")
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testLoginLight() {
        launch(appearance: "Light")
        selectItem("github", name: "GitHub")
        capture("01-login-light")
    }

    func testLoginDark() {
        launch(appearance: "Dark")
        selectItem("github", name: "GitHub")
        capture("02-login-dark")
        app.buttons["vault.toggleSidebar"].click()
        capture("06-sidebar-collapsed")
        app.buttons["vault.toggleSidebar"].click()
        app.typeKey("k", modifierFlags: .command)
        capture("05-search-focused")
        app.typeText("GitHub")
        XCTAssertTrue(element("itemList.row.github").waitForExistence(timeout: 5))
        let filtered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                object: element("itemList.row.apple"))
        XCTAssertEqual(XCTWaiter.wait(for: [filtered], timeout: 5), .completed)
    }

    func testVerificationCodes() {
        launch(appearance: "Light", openCodes: true)
        XCTAssertTrue(element("verificationCodes.row.github").waitForExistence(timeout: 10))
        element("verificationCodes.row.github").click()
        XCTAssertTrue(element("verificationCodes.code.github").exists)
        capture("03-verification-codes")
    }

    func testCard() {
        launch(appearance: "Light")
        selectItem("card", name: "Everyday card")
        XCTAssertTrue(app.staticTexts["Cardholder Name"].firstMatch.waitForExistence(timeout: 5))
        capture("04-card")
    }

    private func launch(appearance: String, openCodes: Bool = false) {
        app.launchArguments = ["--ui-test-vault", "--ui-test-screenshots",
                               "-AppleInterfaceStyle", appearance]
        if openCodes { app.launchArguments.append("--ui-test-open-codes") }
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5),
                      "Launching the app must present its main window")
        let firstRow = openCodes ? "verificationCodes.row.github" : "itemList.row.github"
        XCTAssertTrue(element(firstRow).waitForExistence(timeout: 20))
        let window = app.windows.firstMatch
        let size = window.frame.size
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
            .withOffset(CGVector(dx: -2, dy: -2))
        corner.press(forDuration: 0.1, thenDragTo:
            corner.withOffset(CGVector(dx: 1200 - size.width, dy: 900 - size.height)))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func selectItem(_ id: String, name: String) {
        let row = element("itemList.row.\(id)")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        let title = element("detail.name")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let matchesName = NSPredicate { _, _ in
            title.label == name || title.value as? String == name
                || title.staticTexts[name].firstMatch.exists
        }
        let titleUpdated = XCTNSPredicateExpectation(predicate: matchesName, object: title)
        XCTAssertEqual(XCTWaiter.wait(for: [titleUpdated], timeout: 5), .completed,
                       "The detail title should show \(name)")
    }

    private func capture(_ name: String) {
        app.activate()
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
