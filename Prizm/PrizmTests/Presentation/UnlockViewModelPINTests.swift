import XCTest
@testable import Prizm

@MainActor
final class UnlockViewModelPINTests: XCTestCase {
    func testPINUnlock_clearsInputAndSyncs() async throws {
        let auth = MockAuthRepository()
        auth.pinUnlockAvailable = true
        let sync = MockSyncUseCase()
        let model = UnlockViewModel(auth: auth, sync: sync, account: auth.storedAccount() ?? account)
        model.usePIN = true
        model.password = "123456"
        model.unlock()
        let deadline = ContinuousClock.now + .seconds(2)
        while model.flowState != .vault, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(model.flowState, .vault)
        XCTAssertTrue(sync.executeCalled)
        XCTAssertFalse(auth.unlockWithPasswordCalled)
        XCTAssertEqual(model.password, "")
    }

    private var account: Account {
        Account(userId: "test", email: "test@example.com", name: nil,
                serverEnvironment: ServerEnvironment(base: URL(string: "https://vault.example.com")!, overrides: nil))
    }
}
