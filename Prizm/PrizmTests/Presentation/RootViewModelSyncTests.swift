import XCTest
@testable import Prizm

@MainActor
final class RootViewModelSyncTests: XCTestCase {
    private var auth: MockAuthRepository!
    private var vault: MockVaultRepository!
    private var sync: ControlledSync!
    private var root: RootViewModel!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        auth = MockAuthRepository()
        vault = MockVaultRepository()
        sync = ControlledSync()
        let dependencies = MockRootDependencies(auth: auth, vault: vault)
        dependencies.syncVaultUseCase = sync
        suite = "RootViewModelSyncTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        root = RootViewModel(container: dependencies, preferences: AppPreferences(defaults: defaults))
        try await Task.sleep(for: .milliseconds(20))
        root.screen = .vault
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testManualSync_updatesTimestamp_andRejectsDuplicate() async throws {
        root.syncVault()
        root.syncVault()
        try await waitUntil { self.sync.calls == 1 }
        XCTAssertTrue(root.isSyncing)
        XCTAssertFalse(root.canSync)
        let completed = Date(timeIntervalSince1970: 1_700_000_000)
        sync.finish(at: completed)
        try await waitUntil { !self.root.isSyncing }
        XCTAssertEqual(root.vaultBrowserVM.lastSyncedAt, completed)
        XCTAssertEqual(sync.calls, 1)
    }

    func testSyncFailure_preservesTimestamp_andShowsError() async throws {
        let previous = root.vaultBrowserVM.lastSyncedAt
        root.syncVault()
        try await waitUntil { self.sync.calls == 1 }
        sync.finish(error: SyncError.networkUnavailable)
        try await waitUntil { !self.root.isSyncing }
        XCTAssertNotNil(root.syncError)
        XCTAssertEqual(root.vaultBrowserVM.lastSyncedAt, previous)
    }

    func testLockedVaultAndOpenEditor_doNotStartSync() async throws {
        root.screen = .unlock
        root.syncVault()
        XCTAssertFalse(root.isSyncing)
        root.screen = .vault
        root.vaultBrowserVM.handleEditSheetState(true)
        root.syncVault()
        XCTAssertFalse(root.isSyncing)
        XCTAssertEqual(sync.calls, 0)
    }

    func testLockWaitsForRunningSync_beforeClearingVault() async throws {
        root.syncVault()
        try await waitUntil { self.sync.calls == 1 }
        root.lockVault()
        XCTAssertFalse(root.isVaultUnlocked)
        XCTAssertFalse(root.canSync)
        XCTAssertFalse(vault.clearVaultCalled)
        sync.finish(at: Date())
        try await waitUntil { self.vault.clearVaultCalled }
        XCTAssertEqual(auth.lockVaultCalledCount, 1)
        XCTAssertNil(root.vaultBrowserVM.lastSyncedAt)
    }

    func testLockDuringInitialUnlock_drainsOldViewModelAndStaysLocked() async throws {
        guard case .success(let account) = auth.stubbedLoginResult else { return XCTFail("Missing fixture") }
        auth.stubbedStoredAccount = account
        let oldUnlock = UnlockViewModel(auth: auth, sync: sync, account: account)
        root.unlockVM = oldUnlock
        oldUnlock.password = "test password"
        oldUnlock.unlock()
        try await waitUntil { self.sync.calls == 1 }
        root.lockVault()
        root.handleUnlockFlow(.vault)
        XCTAssertFalse(root.isVaultUnlocked)
        XCTAssertFalse(vault.clearVaultCalled)
        sync.finish(at: Date())
        try await waitUntil { if case .unlock = self.root.screen { return true }; return false }
        XCTAssertFalse(root.unlockVM === oldUnlock)
        XCTAssertTrue(vault.clearVaultCalled)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(root.isVaultUnlocked)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(condition())
    }
}

@MainActor
private final class ControlledSync: SyncUseCase {
    var calls = 0
    private var continuation: CheckedContinuation<SyncResult, any Error>?

    func execute(progress: @Sendable @escaping (String) -> Void) async throws -> SyncResult {
        calls += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func finish(at date: Date) {
        continuation?.resume(returning: SyncResult(syncedAt: date, totalCiphers: 0, failedDecryptionCount: 0))
        continuation = nil
    }

    func finish(error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
