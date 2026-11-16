import XCTest
@testable import Prizm

// MARK: - AboutViewModelTests

/// Unit tests for `AboutViewModel` (FR: About window spec §5).
///
/// `AboutViewModel` is `@MainActor`-isolated (view model, consumed exclusively by SwiftUI
/// views). The test class is annotated `@MainActor` so that XCTAssert autoclosures run on
/// the main actor, satisfying the isolation requirement without async overhead per test.
@MainActor
final class AboutViewModelTests: XCTestCase {

    // Shared instance built with explicit values — no Bundle.main access needed.
    private var sut: AboutViewModel!

    override func setUp() async throws {
        try await super.setUp()
        sut = AboutViewModel(
            appName:  "Luma",
            version:  "1.0",
            tagline:  "Your secrets. Your server. Our user interface.",
            gitHubURL: URL(string: "https://github.com/sk2andy/prizm")!,
            acknowledgements: [
                "Prizm by Benjamin (b0x42) — original app and vault architecture",
                "Vaultwarden & Bitwarden — server API and vault format",
                "Argon2Swift — Argon2id key derivation (RFC 9106)",
            ]
        )
    }

    func testVersion_isNonEmpty() {
        XCTAssertFalse(sut.version.isEmpty)
        XCTAssertEqual(sut.version, "1.0")
    }

    func testGitHubURL_isCorrect() {
        XCTAssertEqual(
            sut.gitHubURL.absoluteString,
            "https://github.com/sk2andy/prizm"
        )
    }

    func testAppName_isNonEmpty() {
        XCTAssertFalse(sut.appName.isEmpty)
    }

    func testTagline_isNonEmpty() {
        XCTAssertFalse(sut.tagline.isEmpty)
    }

    func testAcknowledgements_containsVaultwardenAndArgon2() {
        XCTAssertFalse(sut.acknowledgements.isEmpty)
        XCTAssertTrue(
            sut.acknowledgements.contains(where: { $0.contains("Vaultwarden") || $0.contains("Bitwarden") }),
            "acknowledgements must mention Vaultwarden/Bitwarden API"
        )
        XCTAssertTrue(
            sut.acknowledgements.contains(where: { $0.contains("Argon2") }),
            "acknowledgements must mention Argon2Swift"
        )
    }

    // MARK: - Bundle integration test (main actor)

    func testForCurrentApp_identifiesForkAndCreditsUpstream() {
        let vm = AboutViewModel.forCurrentApp()

        XCTAssertEqual(vm.appName, "Luma")
        XCTAssertEqual(vm.gitHubURL.absoluteString, "https://github.com/sk2andy/prizm")
        XCTAssertTrue(vm.acknowledgements.contains(
            "Prizm by Benjamin (b0x42) — original app and vault architecture"
        ))
    }

    @MainActor
    func testForCurrentApp_versionIsNonEmpty() {
        // Validates that the built app bundle contains CFBundleShortVersionString.
        // This test runs on the main actor because forCurrentApp() reads Bundle.main.
        let vm = AboutViewModel.forCurrentApp()
        XCTAssertFalse(vm.version.isEmpty, "CFBundleShortVersionString must be set in the app bundle")
        XCTAssertFalse(vm.appName.isEmpty, "CFBundleName must be set in the app bundle")
    }
}
