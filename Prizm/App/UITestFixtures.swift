#if DEBUG
import Foundation

/// Seeds an in-memory vault for XCUITest, so UI journeys can run without a server or a login.
///
/// Enabled only by the `--ui-test-vault` launch argument and compiled out of Release builds
/// (`#if DEBUG`), so a shipping password manager contains no test-vault backdoor. The fixtures
/// use made-up names and RFC 6238 test secrets, never real credentials.
enum UITestFixtures {

    static let launchArgument = "--ui-test-vault"

    static var isEnabled: Bool { CommandLine.arguments.contains(launchArgument) }

    /// Richer fictional data for app screenshots; the existing journey fixtures stay stable.
    static var isScreenshotMode: Bool { CommandLine.arguments.contains("--ui-test-screenshots") }

    /// With `--ui-test-open-codes`, start on the Codes list with its first item selected.
    static var opensOnCodes: Bool { CommandLine.arguments.contains("--ui-test-open-codes") }

    /// RFC 6238 Appendix B secret "12345678901234567890" in base32.
    static let rfcSeed = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

    /// With `--ui-test-no-codes`, every sample item has no TOTP seed (to see the empty state).
    static var withoutSeeds: Bool { CommandLine.arguments.contains("--ui-test-no-codes") }

    static var items: [VaultItem] {
        if isScreenshotMode { return screenshotItems }
        let all = seededItems
        guard withoutSeeds else { return all }
        return all.map { login(id: $0.id, name: $0.name, totp: nil, isDeleted: $0.isDeleted) }
    }

    static var folders: [Folder] {
        guard isScreenshotMode else { return [] }
        return [
            Folder(id: "personal", name: "Personal"),
            Folder(id: "work", name: "Work"),
            Folder(id: "travel", name: "Travel"),
        ]
    }

    static var organizations: [Organization] {
        isScreenshotMode ? [Organization(id: "studio", name: "Studio", role: .user)] : []
    }

    static var collections: [OrgCollection] {
        guard isScreenshotMode else { return [] }
        return [
            OrgCollection(id: "engineering", organizationId: "studio", name: "Engineering"),
            OrgCollection(id: "design", organizationId: "studio", name: "Design"),
            OrgCollection(id: "infrastructure", organizationId: "studio", name: "Infrastructure"),
        ]
    }

    private static var screenshotItems: [VaultItem] {
        [
            screenshotLogin(id: "github", name: "GitHub", username: "alex-morgan",
                            isFavorite: true, collectionId: "engineering"),
            screenshotLogin(id: "apple", name: "Apple ID", username: "alex@example.com",
                            isFavorite: true),
            screenshotLogin(id: "proton", name: "Proton Mail", username: "alex@example.com",
                            isFavorite: true),
            screenshotLogin(id: "figma", name: "Figma", username: "alex@example.com",
                            collectionId: "design"),
            screenshotLogin(id: "linear", name: "Linear", username: "alex@example.com",
                            collectionId: "engineering"),
            screenshotLogin(id: "cloudflare", name: "Cloudflare", username: "alex@example.com",
                            collectionId: "infrastructure"),
            screenshotItem(id: "card", name: "Everyday card", content: .card(CardContent(
                cardholderName: "Alex Morgan", brand: "Visa", number: "4242424242424242",
                expMonth: "11", expYear: "2028", code: "123",
                notes: "Sample card for screenshots. Not a payment card.", customFields: []
            )), folderId: "travel"),
            screenshotItem(id: "identity", name: "Alex Morgan", content: .identity(IdentityContent(
                title: nil, firstName: "Alex", middleName: nil, lastName: "Morgan",
                address1: "12 Example Lane", address2: nil, address3: nil,
                city: "Berlin", state: nil, postalCode: "10115", country: "Germany",
                company: "Studio", email: "alex@example.com", phone: nil, ssn: nil,
                username: "alex-morgan", passportNumber: nil, licenseNumber: nil,
                notes: nil, customFields: []
            ))),
            screenshotItem(id: "recovery", name: "Recovery kit", content: .secureNote(SecureNoteContent(
                notes: "A little peace of mind.\n\nKeep account recovery instructions and emergency contacts together.\n\nThis is fictional sample content for the Prizm screenshots.",
                customFields: []
            ))),
        ]
    }

    private static func screenshotLogin(id: String, name: String, username: String,
                                        isFavorite: Bool = false, collectionId: String? = nil) -> VaultItem {
        // Empty URIs keep screenshots offline: FaviconLoader never receives a domain.
        screenshotItem(id: id, name: name, content: .login(LoginContent(
            username: username, password: "screenshot-only-password", uris: [],
            totp: rfcSeed, notes: nil, customFields: []
        )), folderId: collectionId == nil ? "personal" : "work",
                       isFavorite: isFavorite, collectionId: collectionId)
    }

    private static func screenshotItem(id: String, name: String, content: ItemContent,
                                       folderId: String = "personal", isFavorite: Bool = false,
                                       collectionId: String? = nil) -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: isFavorite, isDeleted: false,
            creationDate: Date(timeIntervalSince1970: 1_790_812_800),
            revisionDate: Date(timeIntervalSince1970: 1_794_672_000),
            content: content, folderId: folderId,
            organizationId: collectionId == nil ? nil : "studio",
            collectionIds: collectionId.map { [$0] } ?? []
        )
    }

    private static var seededItems: [VaultItem] {
        [
            login(id: "alpha", name: "Alpha Bank", totp: rfcSeed),
            login(id: "beta", name: "Beta Mail",
                  totp: "otpauth://totp/Beta:me?secret=\(rfcSeed)&digits=8&period=60&algorithm=SHA256"),
            login(id: "gamma", name: "Gamma No Seed", totp: nil),
            login(id: "delta", name: "Delta Bad Seed", totp: "not-a-seed!"),
            login(id: "zeta", name: "Zeta Trashed", totp: rfcSeed, isDeleted: true),
        ]
    }

    private static func login(id: String, name: String, totp: String?, isDeleted: Bool = false) -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: false, isDeleted: isDeleted,
            creationDate: Date(timeIntervalSince1970: 1_700_000_000),
            revisionDate: Date(timeIntervalSince1970: 1_700_000_000),
            content: .login(LoginContent(
                username: "user-\(id)", password: "pw-\(id)", uris: [], totp: totp, notes: nil, customFields: []
            ))
        )
    }
}
#endif
