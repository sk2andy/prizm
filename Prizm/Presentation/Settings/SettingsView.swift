import LocalAuthentication
import SwiftUI
import os.log

/// macOS Settings window (⌘,).
struct SettingsView: View {

    let authRepository: any AuthRepository
    @Bindable var preferences: AppPreferences
    let isVaultUnlocked: Bool
    let canSync: Bool
    let isSyncing: Bool
    let lastSyncedAt: Date?
    let syncError: String?
    let onSync: () -> Void

    private let logger = Logger(subsystem: "com.prizm", category: "SettingsView")

    private var deviceHasBiometrics: Bool {
        var error: NSError?
        let capable = LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        // Skip the routine device states (no hardware, no enrollment, no passcode set) —
        // those are normal, not failures, and would otherwise log on every render (#67).
        if let error, let laError = error as? LAError {
            switch laError.code {
            case .biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet:
                break
            default:
                logger.error("Biometric availability check failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return capable
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $preferences.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                SettingsDurationPicker(
                    title: "Lock after inactivity",
                    disabledTitle: "Never",
                    minutes: $preferences.autoLockMinutes
                )
                Text("Time without keyboard or mouse input in Luma. Using other apps does not reset this timer.")
                    .font(Typography.utility)
                    .foregroundStyle(.secondary)

                Toggle("Lock at a daily time", isOn: $preferences.dailyLockEnabled)
                if preferences.dailyLockEnabled {
                    DatePicker("Daily lock time", selection: dailyLockTime, displayedComponents: .hourAndMinute)
                    Text("Uses your Mac’s local time. If the Mac is asleep, Luma locks when it wakes.")
                        .font(Typography.utility)
                        .foregroundStyle(.secondary)
                }
                Toggle("Lock when the Mac locks", isOn: $preferences.lockOnMacLock)
                Toggle("Lock when the Mac sleeps", isOn: $preferences.lockOnSleep)
                Toggle("Lock when the screen saver starts", isOn: $preferences.lockOnScreenSaver)
            } header: {
                Text("Auto-lock")
            }

            Section("Unlock") {
                PinUnlockSettingsView(authRepository: authRepository, isVaultUnlocked: isVaultUnlocked)
                if deviceHasBiometrics {
                    BiometricUnlockToggle(authRepository: authRepository)
                } else {
                    Text("Biometric unlock requires Touch ID or another supported biometric device.")
                        .font(Typography.utility)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Synchronization") {
                HStack(spacing: Spacing.headerGap) {
                    VStack(alignment: .leading, spacing: Spacing.labelGap) {
                        Text("Vault synchronization")
                        if let lastSyncedAt {
                            Text("Last synced: \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(Typography.utility)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Not synced yet")
                                .font(Typography.utility)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if isSyncing {
                        ProgressView().controlSize(.small)
                    }
                    Button(isSyncing ? "Syncing…" : "Sync now", action: onSync)
                        .disabled(!canSync)
                        .accessibilityHint("Downloads the latest changes from your vault server")
                }
                if !isVaultUnlocked {
                    Text("Unlock your vault to synchronize.")
                        .font(Typography.utility)
                        .foregroundStyle(.secondary)
                }
                if let syncError {
                    Text(syncError)
                        .foregroundStyle(.red)
                        .font(Typography.utility)
                        .accessibilityLabel("Synchronization failed: \(syncError)")
                }
                SettingsDurationPicker(
                    title: "Sync automatically",
                    disabledTitle: "Manually",
                    minutes: $preferences.syncIntervalMinutes
                )
                Text("Automatic sync runs only while the vault is unlocked.")
                    .font(Typography.utility)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 630)
    }

    private var dailyLockTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: preferences.dailyLockHour,
                    minute: preferences.dailyLockMinute,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                preferences.dailyLockHour = components.hour ?? 18
                preferences.dailyLockMinute = components.minute ?? 0
            }
        )
    }
}

/// The two timer settings use the same units and limit, stored as whole minutes.
private struct SettingsDurationPicker: View {
    let title: String
    let disabledTitle: String
    @Binding var minutes: Int
    @State private var custom = false
    @State private var unit = 1

    private let presets = [0, 1, 5, 15, 30, 60, 120, 240, 480]

    private var showsCustomDuration: Bool { custom || !presets.contains(minutes) }

    var body: some View {
        Picker(title, selection: Binding(
            get: { showsCustomDuration ? -1 : minutes },
            set: { value in
                custom = value == -1
                if custom {
                    if minutes == 0 { minutes = 15 }
                    unit = minutes % 60 == 0 ? 60 : 1
                } else {
                    minutes = value
                }
            }
        )) {
            ForEach(presets, id: \.self) { value in
                Text(durationTitle(value)).tag(value)
            }
            Text("Custom…").tag(-1)
        }
        if showsCustomDuration {
            HStack(spacing: Spacing.headerGap) {
                Stepper(
                    value: Binding(get: { max(1, minutes / unit) }, set: { minutes = $0 * unit }),
                    in: 1...(1440 / unit)
                ) {
                    Text("Duration: \(max(1, minutes / unit))")
                }
                Picker("Duration unit", selection: Binding(
                    get: { unit },
                    set: { newUnit in
                        let amount = max(1, minutes / unit)
                        unit = newUnit
                        minutes = min(amount, 1440 / newUnit) * newUnit
                    }
                )) {
                    Text("Minutes").tag(1)
                    Text("Hours").tag(60)
                }
                .labelsHidden()
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(title), custom duration")
        }
    }

    private func durationTitle(_ minutes: Int) -> String {
        switch minutes {
        case 0: disabledTitle
        case 1: "1 minute"
        case 60: "1 hour"
        case let value where value % 60 == 0: "\(value / 60) hours"
        default: "\(minutes) minutes"
        }
    }
}
