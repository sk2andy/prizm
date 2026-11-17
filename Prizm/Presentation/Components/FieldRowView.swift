import SwiftUI

// MARK: - FieldRowView

/// A single labeled field row with hover-activated action buttons (FR-023, FR-025).
///
/// Shows a label + value and reveals copy/reveal/open-in-browser controls on hover.
/// Background highlights on hover to indicate interactivity (FR-023).
///
/// For secret fields (password, card number, etc.) pass `isMasked: true` to show
/// a `MaskedFieldView` instead of plain text; the reveal button will be included automatically.
///
/// Usage:
/// ```swift
/// FieldRowView(label: "Username", value: item.username, itemId: item.id)
/// FieldRowView(label: "Password", value: item.password, itemId: item.id, isMasked: true)
/// FieldRowView(label: "Website", value: uri.uri, itemId: item.id, url: URL(string: uri.uri))
/// ```
struct FieldRowView: View {

    let label:    String
    let value:    String?
    let itemId:   String
    var isMasked: Bool  = false
    var isMultiLine: Bool = false
    var url:      URL?  = nil
    var onCopy:   ((String) -> Void)? = nil

    @State private var isHovered = false
    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.headerGap) {
            if !label.isEmpty {
                Text(label)
                    .font(Typography.fieldLabel)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: isMultiLine ? .top : .center, spacing: Spacing.rowHorizontal) {
                if isMasked {
                    MaskedFieldView(label: label, value: value, itemId: itemId)
                } else {
                    Text(value ?? "—")
                        .font(Typography.fieldValue)
                        .foregroundStyle(Color.primary)
                        .lineLimit(isMultiLine ? nil : 1)
                        .textSelection(.enabled)
                }

                Spacer(minLength: Spacing.headerGap)
                hoverActions
                if !isMasked && !isMultiLine {
                    browserLink
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.fieldRowVertical)
        .padding(.horizontal, Spacing.rowHorizontal)
        .contentShape(Rectangle())
        .onTapGesture { copyValue() }
        .onHover { hovering in
            optionalAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .accessibilityHint(value != nil && !(value?.isEmpty ?? true) ? "Copies \(label) to clipboard" : "")
        .accessibilityIdentifier(AccessibilityID.Field.row(label))
    }

    private func copyValue() {
        guard let copyValue = value, !copyValue.isEmpty else { return }
        onCopy?(copyValue)
        optionalAnimation(.easeInOut(duration: 0.1)) { showCopied = true }
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            optionalAnimation(.easeInOut(duration: 0.1)) { showCopied = false }
        }
    }

    @ViewBuilder
    private var hoverActions: some View {
        if isHovered || showCopied {
            if value != nil, !(value?.isEmpty ?? true) {
                Text(showCopied ? "copied" : "copy")
                    .font(Typography.utility.weight(.medium))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.primary)
                    .padding(.trailing, Spacing.labelGap)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var browserLink: some View {
        if let link = url {
            Link(destination: link) {
                Image(systemName: "arrow.up.right.square")
                    .imageScale(.medium)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            .help("Open in browser")
            .accessibilityLabel("Open \(label)")
            .accessibilityHint("Opens in browser")
            .accessibilityIdentifier(AccessibilityID.Field.openButton(label))
        }
    }
}
