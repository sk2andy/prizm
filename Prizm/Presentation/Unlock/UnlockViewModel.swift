import Combine
import Foundation
import LocalAuthentication
import os.log

// MARK: - UnlockFlowState

enum UnlockFlowState: Equatable {
    case unlock
    case loading
    case syncing(message: String)
    case vault
    /// Returned to login (triggered by "Sign in with a different account").
    case login
}

// MARK: - UnlockViewModel

/// ViewModel for the vault unlock screen (User Story 2).
///
/// The user has a stored session; this screen re-derives the vault key from the
/// master password locally (no network call) then re-syncs the vault.
@MainActor
final class UnlockViewModel: ObservableObject {

    // MARK: - Published state

    @Published var password:        String = ""
    @Published var usePIN = false {
        didSet { password = ""; errorMessage = nil }
    }
    @Published var errorMessage:    String?
    @Published private(set) var flowState: UnlockFlowState = .unlock
    @Published var showEnrollmentPrompt: Bool = false
    @Published private(set) var enrollmentReason: EnrollmentReason = .firstTime

    // MARK: - Dependencies

    private let auth:             any AuthRepository
    private let sync:             any SyncUseCase
    private let account:          Account
    private let embeddedBiometric: (any EmbeddedBiometricUnlock)?
    private let logger = Logger(subsystem: "com.prizm", category: "UnlockViewModel")

    /// Tracks whether the last biometric attempt failed with invalidation,
    /// so the enrollment prompt can show the re-enroll copy.
    private var lastBiometricInvalidated = false

    // MARK: - Biometric context (LAAuthenticationView re-arming)

    /// The current `LAContext` shared with the embedded `LAAuthenticationView`.
    /// Replaced with a fresh instance on each re-arm so the view can re-authenticate.
    @Published private(set) var biometricContext = LAContext()

    /// Incremented on every re-arm so SwiftUI recreates `EmbeddedTouchIDView` via `.id()`.
    @Published private(set) var biometricContextVersion = 0

    private var pendingTasks: [UUID: Task<Void, Never>] = [:]
    private var isCancelling = false
    /// Progress callbacks hop to MainActor in separate tasks; reject callbacks from a cancelled flow.
    private var flowGeneration = 0

    // MARK: - Init

    init(
        auth: any AuthRepository,
        sync: any SyncUseCase,
        account: Account,
        embeddedBiometric: (any EmbeddedBiometricUnlock)? = nil
    ) {
        self.auth              = auth
        self.sync              = sync
        self.account           = account
        self.embeddedBiometric = embeddedBiometric
    }

    // macOS 15: avoid the isolated-deinit crash (swiftlang/swift#88036).
    nonisolated deinit {}

    // MARK: - Derived properties

    /// The stored email, shown read-only in the UI (FR-003).
    var email: String { account.email }

    /// Whether biometric unlock is available for this device and session.
    var biometricUnlockAvailable: Bool { auth.biometricUnlockAvailable }
    var pinUnlockAvailable: Bool { auth.pinUnlockAvailable }
    var pinUnlockEnabled: Bool { auth.pinUnlockEnabled }

    // MARK: - Actions

    func unlock() {
        guard !isCancelling else { return }
        logger.info("Unlock flow started")
        errorMessage = nil
        flowState    = .loading

        // Convert the password String to Data at this boundary so the KDF stack
        // receives `Data` that can be zeroed after use (Constitution §III).
        guard var passwordData = password.data(using: .utf8) else {
            errorMessage = "Invalid password encoding."
            flowState    = .unlock
            return
        }

        let unlockingWithPIN = usePIN
        startTask { [self] in
            defer { passwordData.resetBytes(in: passwordData.indices) }
            do {
                if unlockingWithPIN {
                    _ = try await auth.unlockWithPIN(passwordData)
                } else {
                    _ = try await auth.unlockWithPassword(passwordData)
                }
                guard !Task.isCancelled else { return }
                // Clear the password field after a successful unlock so the plaintext
                // does not linger in the published property.
                password = ""
                await checkEnrollmentOrSync()
            } catch let err as AuthError {
                guard !Task.isCancelled else { return }
                if unlockingWithPIN {
                    password = ""
                    if !auth.pinUnlockAvailable { usePIN = false }
                }
                logger.error("Unlock failed: \(err.localizedDescription, privacy: .public)")
                errorMessage = err.errorDescription
                flowState    = .unlock
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Unlock failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
                flowState    = .unlock
            }
        }
    }

    /// Attempts biometric unlock. On success, proceeds to sync.
    /// On cancellation, re-arms the sensor immediately (always-armed behaviour —
    /// design Decision 2). On lockout or invalidation, shows an error and stops.
    func unlockWithBiometrics() {
        startTask { [self] in
            do {
                _ = try await auth.unlockWithBiometrics()
                guard !Task.isCancelled else { return }
                lastBiometricInvalidated = false
                await checkEnrollmentOrSync()
            } catch let err as AuthError where err == .biometricInvalidated {
                guard !Task.isCancelled else { return }
                lastBiometricInvalidated = true
                errorMessage = err.errorDescription
                flowState = .unlock
                // Intentionally NOT re-arming — invalidation requires password entry.
            } catch let err as AuthError where err == .biometricItemNotFound {
                guard !Task.isCancelled else { return }
                // Keychain item deleted externally — degrade silently, no error shown.
                // biometricUnlockAvailable will return false now (flag cleared in repo).
                _ = err
                flowState = .unlock
            } catch let err as NSError
                where err.domain == NSOSStatusErrorDomain && err.code == Int(errSecUserCanceled) {
                guard !Task.isCancelled else { return }
                // User cancelled — re-arm immediately so the sensor is always ready.
                // No error shown; password field stays available in parallel.
                flowState = .unlock
                triggerBiometricUnlockIfAvailable()
            } catch {
                guard !Task.isCancelled else { return }
                // Lockout or other failure — show the error, stop re-arming.
                errorMessage = error.localizedDescription
                flowState = .unlock
            }
        }
    }

    /// Triggers biometric unlock via the embedded `LAAuthenticationView` path.
    /// Called from `.task(id: biometricContextVersion)` in `UnlockView` so the
    /// `LAAuthenticationView` is guaranteed to be in the window before
    /// `evaluatePolicy` is called — no system modal appears.
    func triggerEmbeddedBiometricIfAvailable() {
        guard biometricUnlockAvailable, let provider = embeddedBiometric else { return }
        startTask { [self] in
            do {
                _ = try await provider.unlockWithBiometrics(context: biometricContext)
                guard !Task.isCancelled else { return }
                lastBiometricInvalidated = false
                await checkEnrollmentOrSync()
            } catch let err as AuthError where err == .biometricInvalidated {
                guard !Task.isCancelled else { return }
                lastBiometricInvalidated = true
                errorMessage = err.errorDescription
                flowState    = .unlock
            } catch let err as AuthError where err == .biometricItemNotFound {
                guard !Task.isCancelled else { return }
                // Keychain item deleted externally — degrade silently, no error shown.
                _ = err
                flowState = .unlock
            } catch let laError as LAError {
                guard !Task.isCancelled else { return }
                switch laError.code {
                case .biometryLockout:
                    // Locked out — show error, stop re-arming.
                    errorMessage = laError.localizedDescription
                    flowState    = .unlock
                default:
                    // Cancellation or transient failure — re-arm silently.
                    rearmBiometrics()
                }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                flowState    = .unlock
            }
        }
    }

    /// Triggers biometric unlock if available; no-op otherwise.
    /// Kept for use when `embeddedBiometric` is nil (test/legacy path).
    func triggerBiometricUnlockIfAvailable() {
        guard biometricUnlockAvailable else { return }
        unlockWithBiometrics()
    }

    /// Replaces `biometricContext` with a fresh `LAContext` and increments the version
    /// counter so `UnlockView` recreates `EmbeddedTouchIDView` via `.id()`.
    func rearmBiometrics() {
        guard !isCancelling, !Task.isCancelled else { return }
        biometricContext        = LAContext()
        biometricContextVersion += 1
    }

    /// Called when the user accepts the enrollment prompt.
    func confirmEnrollBiometric() {
        startTask { [self] in
            do {
                try await auth.enableBiometricUnlock()
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Enable biometric unlock failed: \(error.localizedDescription, privacy: .public)")
            }
            guard !Task.isCancelled else { return }
            UserDefaults.standard.set(true, forKey: "biometricEnrollmentPromptShown")
            showEnrollmentPrompt = false
            await performSync()
        }
    }

    /// Called when the user dismisses the enrollment prompt without enabling.
    func dismissEnrollmentPrompt() {
        guard !isCancelling else { return }
        UserDefaults.standard.set(true, forKey: "biometricEnrollmentPromptShown")
        showEnrollmentPrompt = false
        startTask { [self] in await performSync() }
    }

    /// Clears session and returns to the login screen (FR-039).
    func signInWithDifferentAccount() {
        logger.info("User switching to different account")
        startTask { [self] in
            do {
                try await auth.signOut()
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Sign-out failed: \(error.localizedDescription, privacy: .public)")
            }
            guard !Task.isCancelled else { return }
            flowState = .login
        }
    }

    /// Cancels and drains every authentication/enrollment/sync path before Root clears keys and stores.
    func cancelAndWait() async {
        isCancelling = true
        flowGeneration += 1
        let tasks = Array(pendingTasks.values)
        tasks.forEach { $0.cancel() }
        biometricContext.invalidate()
        showEnrollmentPrompt = false
        password = ""
        errorMessage = nil
        flowState = .unlock
        for task in tasks { await task.value }
        isCancelling = false
    }

    // MARK: - Private

    private func startTask(_ operation: @escaping @MainActor () async -> Void) {
        guard !isCancelling else { return }
        let id = UUID()
        pendingTasks[id] = Task {
            guard !Task.isCancelled else { pendingTasks[id] = nil; return }
            await operation()
            pendingTasks[id] = nil
        }
    }

    /// After a successful unlock, checks whether to show the enrollment prompt sheet
    /// before proceeding to sync.
    ///
    /// Uses `auth.deviceBiometricCapable` (not `biometricUnlockAvailable`) so the check
    /// is mockable in tests and independent of the UserDefaults enabled flag.
    private func checkEnrollmentOrSync() async {
        guard !Task.isCancelled else { return }
        let capable        = auth.deviceBiometricCapable
        let alreadyEnabled = UserDefaults.standard.bool(forKey: "biometricUnlockEnabled")
        let promptShown    = UserDefaults.standard.bool(forKey: "biometricEnrollmentPromptShown")

        if capable && !alreadyEnabled && !promptShown {
            enrollmentReason    = lastBiometricInvalidated ? .reEnrollAfterInvalidation : .firstTime
            showEnrollmentPrompt = true
            // performSync() will be called by confirmEnrollBiometric() or dismissEnrollmentPrompt().
            return
        }
        await performSync()
    }

    private func performSync() async {
        guard !Task.isCancelled else { return }
        let generation = flowGeneration
        flowState = .syncing(message: "Preparing…")
        do {
            _ = try await sync.execute(progress: { [weak self] message in
                Task { @MainActor [weak self] in
                    guard let self, self.flowGeneration == generation else { return }
                    self.flowState = .syncing(message: message)
                }
            })
            guard !Task.isCancelled else { return }
            flowState = .vault
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("Post-unlock sync failed (non-fatal): \(error.localizedDescription, privacy: .public)")
            flowState = .vault
        }
    }
}
