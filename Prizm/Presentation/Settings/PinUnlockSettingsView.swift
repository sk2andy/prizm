import SwiftUI
import os.log

struct PinUnlockSettingsView: View {
    let authRepository: any AuthRepository
    let isVaultUnlocked: Bool

    @State private var isEnabled = false
    @State private var isProcessing = false
    @State private var isEditing = false
    @State private var pin = ""
    @State private var confirmation = ""
    @State private var error: String?
    private let logger = Logger(subsystem: "com.prizm", category: "PinUnlockSettings")

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.headerGap) {
            HStack {
                Text("PIN unlock")
                Spacer()
                if isEnabled {
                    Button("Disable") { Task { await disablePIN() } }
                        .disabled(isProcessing)
                }
                Button(isEnabled ? "Change PIN…" : "Set PIN…") { isEditing = true }
                    .disabled(!isVaultUnlocked || isProcessing)
            }
            Text("After restarting Luma, unlock with your master password once before using your PIN. Five incorrect attempts require the master password again.")
                .font(Typography.utility)
                .foregroundStyle(.secondary)
            if !isVaultUnlocked {
                Text("Unlock your vault to set or change the PIN.")
                    .font(Typography.utility)
                    .foregroundStyle(.secondary)
            }
            if let error, !isEditing {
                Text(error).foregroundStyle(.red).font(Typography.utility)
            }
        }
        .onAppear { isEnabled = authRepository.pinUnlockEnabled }
        .onChange(of: isVaultUnlocked) { _, unlocked in
            isEnabled = authRepository.pinUnlockEnabled
            if !unlocked { isEditing = false; clearInput() }
        }
        .sheet(isPresented: $isEditing, onDismiss: clearInput) {
            VStack(alignment: .leading, spacing: Spacing.detailHeaderGap) {
                Text(isEnabled ? "Change PIN" : "Set PIN").font(Typography.sectionHeader)
                SecureField("PIN (6–12 digits)", text: $pin)
                    .disabled(isProcessing)
                SecureField("Confirm PIN", text: $confirmation)
                    .disabled(isProcessing)
                    .onSubmit { if canSave { Task { await savePIN() } } }
                if let error { Text(error).foregroundStyle(.red).font(Typography.utility) }
                HStack {
                    Spacer()
                    Button("Cancel") { isEditing = false }
                        .keyboardShortcut(.cancelAction)
                        .disabled(isProcessing)
                    Button(isProcessing ? "Saving…" : "Save PIN") { Task { await savePIN() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSave)
                }
            }
            .padding(Spacing.pageMargin)
            .frame(width: 360)
            .interactiveDismissDisabled(isProcessing)
        }
    }

    private var canSave: Bool {
        !isProcessing && isVaultUnlocked && pin == confirmation && (6...12).contains(pin.utf8.count)
            && pin.utf8.allSatisfy { (48...57).contains($0) }
    }

    private func clearInput() { pin = ""; confirmation = ""; error = nil }

    private func savePIN() async {
        guard canSave else { return }
        isProcessing = true
        var bytes = Data(pin.utf8)
        defer { bytes.resetBytes(in: bytes.indices); isProcessing = false }
        do {
            try await authRepository.enablePINUnlock(bytes)
            isEnabled = true
            isEditing = false
            clearInput()
        } catch {
            self.error = error.localizedDescription
            logger.error("PIN setup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func disablePIN() async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            try await authRepository.disablePINUnlock()
            isEnabled = false
            clearInput()
        } catch {
            self.error = error.localizedDescription
            logger.error("PIN removal failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
