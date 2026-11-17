import Combine
import XCTest
@testable import Prizm

/// A Mac lock must wait for the initial sync as well as manual/background refreshes.
@MainActor
final class AuthenticationCancellationTests: XCTestCase {
    private let account = Account(
        userId: "cancel-user", email: "cancel@example.com", name: nil,
        serverEnvironment: ServerEnvironment(base: URL(string: "https://vault.example.com")!, overrides: nil)
    )

    func testLoginCancellation_waitsForInitialSyncAndDoesNotPublishVault() async {
        let useCase = SuspendedLogin(account: account)
        let model = LoginViewModel(loginUseCase: useCase)
        let started = expectation(description: "initial login and sync started")
        useCase.onStart = { started.fulfill() }
        model.password = "test password"
        model.signIn()
        await fulfillment(of: [started], timeout: 1)

        let reset = expectation(description: "login cancelled")
        let observation = model.$flowState.filter { $0 == .login }.sink { _ in reset.fulfill() }
        var finished = false
        let cancellation = Task { await model.cancelAndWait(); finished = true }
        await fulfillment(of: [reset], timeout: 1)
        XCTAssertFalse(finished, "Root must not clear the vault until the initial sync returns")
        useCase.finish()
        await cancellation.value
        XCTAssertEqual(model.flowState, .login)
        XCTAssertEqual(model.password, "")
        XCTAssertTrue(useCase.cancelTOTPCalled)
        withExtendedLifetime(observation) {}
    }

    func testUnlockCancellation_drainsSuccessfulSyncAndIgnoresLateProgress() async {
        await checkUnlockCancellation(syncFails: false)
    }

    func testUnlockCancellation_doesNotTreatCancelledSyncAsNonfatalUnlockSuccess() async {
        await checkUnlockCancellation(syncFails: true)
    }

    private func checkUnlockCancellation(syncFails: Bool) async {
        let auth = MockAuthRepository()
        auth.stubbedLoginResult = .success(account)
        let sync = SuspendedSync()
        let model = UnlockViewModel(auth: auth, sync: sync, account: account)
        let started = expectation(description: "post-unlock sync started")
        sync.onStart = { started.fulfill() }
        model.password = "test password"
        model.unlock()
        await fulfillment(of: [started], timeout: 1)

        let reset = expectation(description: "unlock cancelled")
        let observation = model.$flowState.filter { $0 == .unlock }.sink { _ in reset.fulfill() }
        var finished = false
        let cancellation = Task { await model.cancelAndWait(); finished = true }
        await fulfillment(of: [reset], timeout: 1)
        XCTAssertFalse(finished)
        sync.finish(fails: syncFails)
        await cancellation.value
        XCTAssertEqual(model.flowState, .unlock)

        // Callback already dispatched by a sync must not revive its old view model after cancellation.
        sync.progress?("Late progress")
        let forbidden = expectation(description: "no stale progress or vault transition")
        forbidden.isInverted = true
        let lateObservation = model.$flowState.dropFirst().sink { _ in forbidden.fulfill() }
        await fulfillment(of: [forbidden], timeout: 0.05)
        XCTAssertEqual(model.flowState, .unlock)
        withExtendedLifetime((observation, lateObservation)) {}
    }
}

@MainActor
private final class SuspendedLogin: LoginUseCase {
    let account: Account
    var onStart: (() -> Void)?
    private var continuation: CheckedContinuation<LoginResult, Never>?
    private(set) var cancelTOTPCalled = false

    init(account: Account) { self.account = account }

    func execute(serverURL: String, email: String, masterPassword: Data) async throws -> LoginResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            onStart?()
        }
    }

    func completeTOTP(code: String, rememberDevice: Bool) async throws -> Account { account }
    func cancelTOTP() { cancelTOTPCalled = true }
    func finish() { continuation?.resume(returning: .success(account)); continuation = nil }
}

@MainActor
private final class SuspendedSync: SyncUseCase {
    var onStart: (() -> Void)?
    var progress: (@Sendable (String) -> Void)?
    private var continuation: CheckedContinuation<SyncResult, any Error>?

    func execute(progress: @Sendable @escaping (String) -> Void) async throws -> SyncResult {
        self.progress = progress
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            onStart?()
        }
    }

    func finish(fails: Bool) {
        if fails {
            continuation?.resume(throwing: CancellationError())
        } else {
            continuation?.resume(returning: SyncResult(syncedAt: Date(), totalCiphers: 1, failedDecryptionCount: 0))
        }
        continuation = nil
    }
}
