import SwiftUI

struct ItemSelectionBackground: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            // Cover the native blue selection beneath the inset rounded surface.
            Color("CardBackground")
            RoundedRectangle(cornerRadius: Spacing.itemIconCornerRadius)
                .fill(isSelected ? Palette.listSelection : .clear)
                .padding(.horizontal, Spacing.headerGap)
                .padding(.vertical, 2)
        }
    }
}

// MARK: - CardBackground

/// A `ViewModifier` that renders any view inside a card-style container:
/// rounded corners, a light/dark background, and a contrast-aware outline.
///
/// Adapted from: https://danijelavrzan.com/posts/2023/02/card-view-swiftui/
struct CardBackground: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(Color("CardBackground"))
            .clipShape(RoundedRectangle(cornerRadius: Spacing.contentCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.contentCornerRadius)
                    .stroke(Color.primary.opacity(Opacity.cardBorder(contrast)), lineWidth: 0.5)
            )
    }
}

extension View {
    /// Applies rounded corners, an adaptive background, and a contrast-aware outline.
    func cardBackground() -> some View {
        modifier(CardBackground())
    }
}

// MARK: - DetailSectionCard

/// A card-style section container for vault item detail views.
///
/// Renders an optional section header label above a group of field rows,
/// all wrapped in a `cardBackground()`. Used by all five type-specific detail
/// views to group related fields visually.
///
/// Usage:
/// ```swift
/// DetailSectionCard("Credentials") {
///     FieldRowView(label: "Username", ...)
///     Divider()
///     FieldRowView(label: "Password", ...)
/// }
/// ```
struct DetailSectionCard<Content: View>: View {

    private let title: String?
    private let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.headerGap) {
            if Self.hasHeader(title) {
                Text(title!)
                    .font(Typography.fieldLabelProminent)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(
                        AccessibilityID.Detail.cardHeader(title!)
                    )
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .cardBackground()
        }
        .padding(.horizontal, Spacing.pageMargin)
        .padding(.top, Spacing.cardTop)
        .padding(.bottom, Spacing.cardBottom)
    }

    // MARK: - Testable header logic

    /// Returns `true` when the card should render a visible section header.
    ///
    /// A nil or whitespace-only title means no header is rendered — the card
    /// appears without a label above it.
    static func hasHeader(_ title: String?) -> Bool {
        guard let title else { return false }
        return !title.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
