//
//  PrizmApp.swift
//  Prizm
//
//  Created by Benjamin on 15.03.26.
//

import AppKit
import Combine
import Observation
import SwiftUI
import os.log

@main
struct PrizmApp: App {

    @StateObject private var container: AppContainer
    @StateObject private var rootVM:    RootViewModel
    @State       private var optionKeyMonitor = OptionKeyMonitor()
    @State       private var systemAppearance = SystemAppearance()

    // Used by the About menu item to open the custom About window scene.
    @Environment(\.openWindow) private var openWindow

    init() {
        let c = AppContainer()
        _container = StateObject(wrappedValue: c)
        _rootVM    = StateObject(wrappedValue: RootViewModel(container: c))
    }

    var body: some Scene {
        WindowGroup("Luma", id: "vault") {
            rootView
                .frame(minWidth: rootVM.isVaultUnlocked ? nil : 480,
                       minHeight: rootVM.isVaultUnlocked ? nil : 360)
                .environment(optionKeyMonitor)
                .preferredColorScheme(preferredColorScheme)
                .environment(\.colorScheme, preferredColorScheme)
                .tint(Color("AccentColor"))
                .onAppear { rootVM.startAutomation() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 1100, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            // Replace the default "About Prizm" panel with our custom SwiftUI window.
            CommandGroup(replacing: .appInfo) {
                Button("About Luma") {
                    openWindow(id: "about")
                }
            }

            CommandGroup(after: .textEditing) {
                Button("Search Vault") { rootVM.vaultBrowserVM.triggerSearch() }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(!rootVM.isVaultUnlocked)
                Button("Quick Search") { rootVM.vaultBrowserVM.triggerSearch() }
                    .keyboardShortcut("k", modifiers: .command)
                    .disabled(!rootVM.isVaultUnlocked)
            }

            CommandGroup(after: .appInfo) {
                Button("Sign Out…") {
                    rootVM.confirmSignOut()
                }
                .keyboardShortcut("q", modifiers: [.command, .shift])
                .disabled(!rootVM.isSignedIn)

                Button("Sync Vault Now") { rootVM.syncVault() }
                    .disabled(!rootVM.canSync)
                    .keyboardShortcut("r", modifiers: .command)

                Button("Lock Vault") {
                    rootVM.lockVault()
                }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(!rootVM.isVaultUnlocked)
            }

            // "Item" menu — sits in the standard macOS menu bar next to Edit/View/Window.
            // Edit opens the edit sheet for the selected vault item (⌘E).
            // Save persists in-flight edits (⌘S).
            // Buttons are disabled by `rootVM` Combine subscriptions that track
            // item selection and edit-sheet state.
            CommandMenu("Item") {
                Button("Edit") {
                    rootVM.vaultBrowserVM.triggerEdit()
                }
                .disabled(!rootVM.menuBarCanEdit)
                .keyboardShortcut("e", modifiers: .command)

                Button("Save") {
                    rootVM.vaultBrowserVM.triggerSave()
                }
                .disabled(!rootVM.menuBarCanSave)
                .keyboardShortcut("s", modifiers: .command)

                Divider()

                Button("Copy Username") {
                    rootVM.copySelectedField(.username)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!rootVM.selectedFieldAvailable(.username))

                Button("Copy Password") {
                    rootVM.copySelectedField(.password)
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(!rootVM.selectedFieldAvailable(.password))

                Button("Copy Code") {
                    rootVM.copySelectedField(.totp)
                }
                .keyboardShortcut("c", modifiers: [.command, .control])
                .disabled(!rootVM.selectedFieldAvailable(.totp))

                Button("Copy Website") {
                    rootVM.copySelectedField(.website)
                }
                .keyboardShortcut("c", modifiers: [.command, .option, .shift])
                .disabled(!rootVM.selectedFieldAvailable(.website))
            }
        }

        // Custom About window — opened via Prizm → About Prizm.
        // hiddenTitleBar: AboutView provides its own header with the app icon and name,
        // so the system title bar would be redundant.
        // contentSize resizability: window sizes to AboutView's fixed 380pt width; no
        // free resize since the content is a fixed-layout info panel.
        Window("About Luma", id: "about") {
            AboutView()
                .preferredColorScheme(preferredColorScheme)
                .environment(\.colorScheme, preferredColorScheme)
                .tint(Color("AccentColor"))
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        // Settings window — opened via ⌘, (macOS convention) or the gear toolbar button.
        // The Settings scene does not inherit the WindowGroup environment, so we pass
        // the container explicitly via .environmentObject().
        Settings {
            SettingsView(
                authRepository: container.authRepository,
                preferences: rootVM.preferences,
                isVaultUnlocked: rootVM.isVaultUnlocked,
                canSync: rootVM.canSync,
                isSyncing: rootVM.isSyncing,
                lastSyncedAt: rootVM.vaultBrowserVM.lastSyncedAt,
                syncError: rootVM.syncError,
                onSync: { rootVM.syncVault() }
            )
            .preferredColorScheme(preferredColorScheme)
            .environment(\.colorScheme, preferredColorScheme)
            .tint(Color("AccentColor"))
        }
    }

    private var preferredColorScheme: ColorScheme {
        #if DEBUG
        if UITestFixtures.isEnabled && UITestFixtures.isScreenshotMode {
            return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? .dark : .light
        }
        #endif
        return rootVM.preferences.appearance.colorScheme ?? systemAppearance.colorScheme
    }

    @ViewBuilder
    private var rootView: some View {
        switch rootVM.screen {
        case .login:
            LoginView(viewModel: rootVM.loginVM)

        case .locking:
            ProgressView("Locking vault…")
                .frame(minWidth: 480, minHeight: 360)

        case .loading:
            ProgressView("Signing in…")
                .frame(minWidth: 480, minHeight: 360)

        case .totpPrompt:
            TOTPPromptView(viewModel: rootVM.loginVM)

        case .unlock:
            if let unlockVM = rootVM.unlockVM {
                UnlockView(viewModel: unlockVM)
            }

        case .syncing(let message):
            SyncProgressView(message: message)

        case .vault:
            VaultBrowserView(
                viewModel:         rootVM.vaultBrowserVM,
                faviconLoader:     container.faviconLoader,
                accountLabel:      rootVM.accountLabel,
                makeEditViewModel: { [vaultBrowserVM = rootVM.vaultBrowserVM] item in
                    let vm = container.makeItemEditViewModel(
                        for: item,
                        folders: vaultBrowserVM.folders,
                        organizations: vaultBrowserVM.organizations,
                        collections: vaultBrowserVM.collections
                    )
                    // Wire the list-pane refresh callback to the shared VaultBrowserViewModel.
                    vm.onSaveSuccess = { [weak vaultBrowserVM] updatedItem in
                        vaultBrowserVM?.handleItemSaved(updatedItem)
                    }
                    return vm
                },
                makeCreateViewModel: { [vaultBrowserVM = rootVM.vaultBrowserVM] type, contextId in
                    // contextId is either a folderId (personal item) or collectionId (org item),
                    // determined by whether the current sidebar selection is a collection.
                    let cols = vaultBrowserVM.collections
                    let isCollection = contextId != nil && cols.contains(where: { $0.id == contextId })
                    let vm: ItemEditViewModel
                    if isCollection {
                        vm = container.makeItemCreateViewModel(
                            for: type, collectionId: contextId,
                            folders: vaultBrowserVM.folders, organizations: vaultBrowserVM.organizations, collections: cols
                        )
                    } else {
                        vm = container.makeItemCreateViewModel(
                            for: type, folderId: contextId,
                            folders: vaultBrowserVM.folders, organizations: vaultBrowserVM.organizations, collections: cols
                        )
                    }
                    vm.onSaveSuccess = { [weak vaultBrowserVM] item in
                        vaultBrowserVM?.handleItemSaved(item)
                    }
                    return vm
                },
                makeAddAttachmentViewModel: { cipherId in
                    container.makeAddAttachmentViewModel(for: cipherId)
                },
                makeBatchAttachmentViewModel: { cipherId in
                    container.makeBatchAttachmentViewModel(for: cipherId)
                },
                makeAttachmentRowViewModel: { cipherId, attachment in
                    container.makeAttachmentRowViewModel(cipherId: cipherId, attachment: attachment)
                },
                makeCodesViewModel: { container.makeTOTPCodesViewModel() }
            )
        }
    }
}

// MARK: - RootViewModel

/// Dependencies required by `RootViewModel` — extracted for testability.
@MainActor
protocol RootViewModelDependencies: AnyObject {
    var authRepo: any AuthRepository { get }
    var vaultRepo: any VaultRepository { get }
    var syncVaultUseCase: any SyncUseCase { get }
    /// Generates the current TOTP code for the "Copy Code" command.
    var generateTOTPCode: any GenerateTOTPCodeUseCase { get }
    /// The per-cipher attachment key cache. Cleared on vault lock alongside the vault store.
    var vaultKeyCache: VaultKeyCache { get }
    /// The per-organisation symmetric key cache. Cleared on vault lock alongside the vault store.
    var orgKeyCache: OrgKeyCache { get }
    func makeLoginViewModel() -> LoginViewModel
    func makeUnlockViewModel(account: Account) -> UnlockViewModel
    func makeVaultBrowserViewModel() -> VaultBrowserViewModel
    /// Returns a fresh sync timestamp repository and use case scoped to the given email.
    /// Called after login/unlock to re-scope to the correct account before the first sync.
    func makeSyncTimestampDependencies(for email: String) -> (repository: any SyncTimestampRepository, useCase: any GetLastSyncDateUseCase)
}

extension AppContainer: RootViewModelDependencies {
    var authRepo: any AuthRepository { authRepository }
    var vaultRepo: any VaultRepository { vaultStore }
    var syncVaultUseCase: any SyncUseCase { syncUseCase }
    var generateTOTPCode: any GenerateTOTPCodeUseCase { generateTOTPCodeUseCase }
}

/// Top-level state machine that decides which screen to show.
///
/// On launch: checks for a stored session via `AuthRepository.storedAccount()`.
/// - Session found → `UnlockView` (User Story 2)
/// - No session    → `LoginView`  (User Story 1)
@MainActor
final class RootViewModel: ObservableObject {

    enum Screen {
        case login
        case loading
        case locking
        case totpPrompt
        case unlock
        case syncing(message: String)
        case vault
    }

    @Published var screen: Screen
    @Published private(set) var isSyncing = false
    @Published private(set) var syncError: String?
    let preferences: AppPreferences

    private var automation = VaultAutomation(now: Date())
    private var syncTask: Task<Void, Never>?
    nonisolated(unsafe) private var automationTask: Task<Void, Never>?
    nonisolated(unsafe) private var activityMonitor: Any?

    // MARK: - "Item" menu state

    /// Whether the Edit command should be enabled: an item is selected and the edit sheet is closed.
    @Published private(set) var menuBarCanEdit: Bool = false

    /// Whether the Save command should be enabled: the edit sheet is currently open.
    @Published private(set) var menuBarCanSave: Bool = false

    /// The login content of the currently selected item, or nil. Drives copy command disabled state.
    @Published private(set) var selectedLogin: LoginContent?

    private let logger = Logger(subsystem: "com.prizm", category: "RootViewModel")

    let loginVM:          LoginViewModel
    @Published var unlockVM: UnlockViewModel?
    let vaultBrowserVM:   VaultBrowserViewModel

    private let container: any RootViewModelDependencies
    /// Combine subscriptions — held for the lifetime of this object.
    /// Using Combine (not SwiftUI .onChange) so transitions fire regardless
    /// of whether the source view is currently in the view hierarchy.
    private var cancellables = Set<AnyCancellable>()
    /// System notification observers for auto-lock (sleep, screensaver, screen lock).
    nonisolated(unsafe) private var sleepObserver: NSObjectProtocol?
    nonisolated(unsafe) private var screensaverObserver: NSObjectProtocol?
    nonisolated(unsafe) private var screenLockObserver: NSObjectProtocol?

    init(container: any RootViewModelDependencies, preferences: AppPreferences = AppPreferences()) {
        self.preferences = preferences
        self.container      = container
        self.loginVM        = container.makeLoginViewModel()
        self.vaultBrowserVM = container.makeVaultBrowserViewModel()

        // Check for stored session at launch.
        if let account = container.authRepo.storedAccount() {
            self.screen   = .unlock
            self.unlockVM = container.makeUnlockViewModel(account: account)
        } else {
            self.screen   = .login
            self.unlockVM = nil
        }

        subscribeToFlowStates()

        #if DEBUG
        // XCUITest seam: skip login and show a seeded in-memory vault (see UITestFixtures).
        if UITestFixtures.isEnabled {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await container.vaultRepo.populate(
                    items: UITestFixtures.items, folders: UITestFixtures.folders,
                    organizations: UITestFixtures.organizations,
                    collections: UITestFixtures.collections, syncedAt: Date()
                )
                self.transitionToVault(caller: "UITestFixtures")

                // Optional: open straight on the Codes list with an item selected (screenshots).
                if UITestFixtures.opensOnCodes {
                    try? await Task.sleep(for: .milliseconds(600))
                    self.vaultBrowserVM.sidebarSelection = .verificationCodes
                    try? await Task.sleep(for: .milliseconds(600))
                    self.vaultBrowserVM.itemSelection = self.vaultBrowserVM.displayedItems.first
                }
            }
        }
        #endif
    }

    deinit {
        automationTask?.cancel()
        if let activityMonitor { NSEvent.removeMonitor(activityMonitor) }
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let screensaverObserver { DistributedNotificationCenter.default().removeObserver(screensaverObserver) }
        if let screenLockObserver { DistributedNotificationCenter.default().removeObserver(screenLockObserver) }
    }

    // MARK: - Combine subscriptions

    private func subscribeToFlowStates() {
        // Login flow — observe for the lifetime of the app (loginVM is never replaced).
        loginVM.$flowState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.handleLoginFlow(state) }
            .store(in: &cancellables)

        // Unlock flow — re-subscribe whenever unlockVM is assigned.
        $unlockVM
            .map { viewModel -> AnyPublisher<UnlockFlowState, Never> in
                viewModel?.$flowState.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()
            }
            .switchToLatest()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.handleUnlockFlow(state) }
            .store(in: &cancellables)

        // canEdit: item selected AND edit sheet not yet open.
        // canSave: edit sheet is open.
        // Both are derived by watching editSheetOpen and itemSelection independently.
        // `for await` on @Published.values avoids Combine callbacks (CLAUDE.md async/await rule).
        Task { [weak self, vaultBrowserVM] in
            for await open in vaultBrowserVM.$editSheetOpen.values {
                guard let self else { break }
                self.menuBarCanSave = open
                self.menuBarCanEdit = vaultBrowserVM.itemSelection != nil && !open
            }
        }
        Task { [weak self, vaultBrowserVM] in
            for await selection in vaultBrowserVM.$itemSelection.values {
                guard let self else { break }
                self.menuBarCanEdit = selection != nil && !vaultBrowserVM.editSheetOpen
                if case .login(let login) = selection?.content {
                    self.selectedLogin = login
                } else {
                    self.selectedLogin = nil
                }
            }
        }

        // Auto-lock on Mac sleep.
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated {
            guard let self, self.preferences.lockOnSleep else { return }
            self.lockVault()
        } }

        // Auto-lock on screensaver start.
        screensaverObserver = DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screensaver.didstart"),
            object: nil,
            queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated {
            guard let self, self.preferences.lockOnScreenSaver else { return }
            self.lockVault()
        } }

        // Auto-lock on screen lock (⌃⌘Q / Lock Screen menu).
        screenLockObserver = DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated {
            guard let self, self.preferences.lockOnMacLock else { return }
            self.lockVault()
        } }
    }

    /// Re-scopes the sync timestamp to the current account and records a successful sync,
    /// then transitions to the vault screen.
    ///
    /// Called from both `handleLoginFlow` and `handleUnlockFlow` — the vault transition
    /// logic is identical in both flows. `caller` is included in the error log so the
    /// originating flow is identifiable when the account is unexpectedly missing.
    private func transitionToVault(caller: String) {
        // Re-scope before recording: on first login the AppContainer was initialised without
        // a known email; this corrects the UserDefaults key before handleSyncCompleted writes to it.
        if let email = container.authRepo.storedAccount()?.email {
            let deps = container.makeSyncTimestampDependencies(for: email)
            vaultBrowserVM.updateSyncTimestamp(repository: deps.repository, useCase: deps.useCase)
        } else {
            // Unexpected: vault transition reached with no stored account — timestamp will
            // be written under the fallback empty-email key. Should not occur in normal flow.
            logger.error("\(caller, privacy: .public)(.vault): no stored account; sync timestamp not re-scoped")
        }
        screen = .vault
        automation = VaultAutomation(now: Date())
        syncError = nil
        // Defer handleSyncCompleted to the next run-loop cycle so that the initial
        // VaultBrowserView layout pass (triggered by `screen = .vault` above) commits
        // before any @Published mutations from async vault reads arrive.
        //
        // Root cause: VaultRepositoryImpl is an `actor`, so every refresh Task suspends
        // at a cross-actor hop; the continuations resume on @MainActor asynchronously.
        // If they land while SwiftUI is computing its first layout pass for VaultBrowserView,
        // SwiftUI emits "Publishing changes from within view updates is not allowed" →
        // undefined behaviour → heap corruption → z_ccm_xcma_malloc_freelist EXC_BREAKPOINT.
        //
        // DispatchQueue.main.async (not a Swift Task) is intentional: it guarantees
        // the block runs between run-loop iterations, after the current CATransaction
        // (which drives the SwiftUI layout commit) has flushed.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.vaultBrowserVM.handleSyncCompleted(syncedAt: Date())
            }
        }
    }

    func handleLoginFlow(_ state: LoginFlowState) {
        if case .locking = screen { return }
        switch state {
        case .login:       screen = .login
        case .loading:     screen = .loading
        case .totpPrompt:  screen = .totpPrompt
        case .syncing(let msg): screen = .syncing(message: msg)
        case .vault:       transitionToVault(caller: "handleLoginFlow")
        }
        logger.info("Screen transition → \(String(describing: state))")
    }

    /// Whether the user has an active session (vault or unlock screen).
    var isSignedIn: Bool {
        switch screen {
        case .vault, .unlock, .syncing, .locking: return true
        default: return false
        }
    }

    /// Shows a confirmation alert before signing out (FR-014).
    func confirmSignOut() {
        let alert = NSAlert()
        alert.messageText = "Sign Out"
        alert.informativeText = "All local data will be cleared."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Sign Out")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        signOut()
    }

    /// Clears all session data and returns to the login screen.
    func signOut() {
        if case .locking = screen { return }
        vaultBrowserVM.resetNavigationHistory()
        screen = .locking
        syncTask?.cancel()
        Task {
            await loginVM.cancelAndWait()
            await unlockVM?.cancelAndWait()
            await syncTask?.value
            do {
                try await container.authRepo.signOut()
            } catch {
                logger.error("Sign-out error: \(error.localizedDescription, privacy: .public)")
            }
            await container.vaultRepo.clearVault()
            await container.vaultKeyCache.clear()
            await container.orgKeyCache.clear()
            unlockVM = nil
            screen   = .login
            logger.info("Sign out completed")
        }
    }

    // MARK: - Lock

    /// Zeros in-memory key material, clears the vault cache, and transitions to the unlock screen.
    /// No-op if the vault is not currently unlocked.
    func lockVault() {
        guard canLockVault else { return }
        vaultBrowserVM.resetNavigationHistory()
        screen = .locking
        syncTask?.cancel()
        Task {
            // Drain authentication and refresh before clearing caches so neither can reopen the vault.
            await loginVM.cancelAndWait()
            await unlockVM?.cancelAndWait()
            await syncTask?.value
            await container.authRepo.lockVault()
            await container.vaultRepo.clearVault()
            // Clear all key caches in the same lock path as the vault store.
            // Key material must not outlive the vault session (Constitution §III).
            await container.vaultKeyCache.clear()
            await container.orgKeyCache.clear()
            if let account = container.authRepo.storedAccount() {
                unlockVM = container.makeUnlockViewModel(account: account)
                screen = .unlock
            } else {
                screen = .login
            }
            logger.info("Vault locked")
        }
    }

    private var canLockVault: Bool {
        switch screen {
        case .vault, .syncing, .loading: return true
        case .unlock: return unlockVM?.flowState == .loading || unlockVM?.showEnrollmentPrompt == true
        default: return false
        }
    }

    var accountLabel: String {
        #if DEBUG
        if UITestFixtures.isEnabled { return "Alex Morgan" }
        #endif
        let email = unlockVM?.email ?? loginVM.email
        return email.isEmpty ? "Vault unlocked" : email
    }

    /// Whether the vault is currently unlocked (vault browser or sync in progress).
    var isVaultUnlocked: Bool {
        switch screen {
        case .vault, .syncing: return true
        default: return false
        }
    }

    func handleUnlockFlow(_ state: UnlockFlowState) {
        if case .locking = screen { return }
        switch state {
        case .unlock:       screen = .unlock
        case .loading:      screen = .unlock   // stay on unlock screen with spinner
        case .syncing(let msg): screen = .syncing(message: msg)
        case .vault:        transitionToVault(caller: "handleUnlockFlow")
        case .login:
            // "Sign in with a different account" — reset to login.
            unlockVM = nil
            screen   = .login
        }
        logger.info("Screen transition → \(String(describing: state))")
    }

    // MARK: - Scheduled locking and refresh

    var canSync: Bool {
        guard case .vault = screen else { return false }
        return !isSyncing && !vaultBrowserVM.editSheetOpen
    }

    func startAutomation() {
        guard automationTask == nil else { return }
        // AppKit exposes app-local input without Accessibility or Input Monitoring permission.
        activityMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel
        ]) { [weak self] event in
            MainActor.assumeIsolated { self?.automation.recordActivity(at: Date()) }
            return event
        }
        automationTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
                self?.checkAutomation(at: Date())
            }
        }
    }

    func checkAutomation(at now: Date) {
        guard case .vault = screen else { return }
        switch automation.check(at: now, preferences: preferences) {
        case .lock: lockVault()
        case .sync: syncVault()
        case nil: break
        }
    }

    func syncVault() {
        guard canSync else { return }
        isSyncing = true
        syncError = nil
        automation.recordSync(at: Date())
        syncTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isSyncing = false }
            do {
                let result = try await self.container.syncVaultUseCase.execute(progress: { _ in })
                guard !Task.isCancelled, case .vault = self.screen else { return }
                self.vaultBrowserVM.handleSyncCompleted(syncedAt: result.syncedAt)
            } catch {
                guard !Task.isCancelled, case .vault = self.screen else { return }
                self.syncError = error.localizedDescription
                self.vaultBrowserVM.handleSyncError(error.localizedDescription)
                self.logger.error("Vault refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Copy field from selected item

    enum CopyableField {
        case username, password, totp, website
    }

    func copySelectedField(_ field: CopyableField) {
        // Copy Code copies the *generated* code, never the stored seed (FR-016, FR-017).
        if field == .totp {
            Task { await copySelectedCode() }
            return
        }
        guard let value = selectedFieldValue(field) else { return }
        vaultBrowserVM.copy(value)
    }

    func selectedFieldAvailable(_ field: CopyableField) -> Bool {
        if field == .totp {
            guard let seed = selectedLogin?.totp else { return false }
            return (try? TOTPSeedParser.parse(seed)) != nil
        }
        return selectedFieldValue(field) != nil
    }

    /// Generates the current code for the selected Login and puts it on the clipboard through the
    /// shared path, so the 30-second auto-clear applies. Does nothing for an unusable seed.
    func copySelectedCode() async {
        guard let seed = selectedLogin?.totp, selectedFieldAvailable(.totp) else { return }
        do {
            let code = try await container.generateTOTPCode.execute(seed: seed, at: Date())
            vaultBrowserVM.copy(code.copyValue)
        } catch {
            // Never log the seed or the error payload (Constitution §III, §V).
            logger.error("Copy Code skipped: the stored seed is not usable")
        }
    }

    private func selectedFieldValue(_ field: CopyableField) -> String? {
        guard let login = selectedLogin else { return nil }

        switch field {
        case .username: return login.username
        case .password: return login.password
        case .website:  return login.uris.first?.uri
        case .totp:     return nil   // handled by copySelectedCode(); the seed is never copied
        }
    }
}

/// Resolve System independently of a window's previous override. SwiftUI can retain the
/// old content appearance when preferredColorScheme changes back to nil on macOS 15.
@Observable
@MainActor
final class SystemAppearance {
    private(set) var colorScheme: ColorScheme
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init(application: NSApplication = .shared) {
        colorScheme = application.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        observation = application.observe(\.effectiveAppearance, options: [.new]) { [weak self] app, _ in
            let isDark = app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            Task { @MainActor [weak self] in self?.colorScheme = isDark ? .dark : .light }
        }
    }

    nonisolated deinit {}
}
