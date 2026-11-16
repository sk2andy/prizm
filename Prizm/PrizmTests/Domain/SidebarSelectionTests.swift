import XCTest
@testable import Prizm

@MainActor
final class SidebarSelectionTests: XCTestCase {

    private let others: [SidebarSelection] = [
        .allItems, .personal, .favorites, .type(.login), .folder("f"), .trash, .newFolder,
        .organization("o"), .collection("c"), .newCollection(organizationId: "o"),
    ]

    func test_verificationCodes_equalsOnlyItself() {
        XCTAssertEqual(SidebarSelection.verificationCodes, .verificationCodes)
        for other in others {
            XCTAssertNotEqual(SidebarSelection.verificationCodes, other)
        }
    }

    func test_verificationCodes_hashesDistinctlyFromEveryOtherCase() {
        let hashes = Set((others + [.verificationCodes]).map(\.hashValue))
        XCTAssertEqual(hashes.count, others.count + 1)
    }

    func test_verificationCodes_displayName() {
        XCTAssertEqual(SidebarSelection.verificationCodes.displayName, "Codes")
    }

    func test_personal_isDistinctFromAllItemsAndOrganizations() {
        XCTAssertEqual(SidebarSelection.personal, .personal)
        XCTAssertNotEqual(SidebarSelection.personal, .allItems)
        XCTAssertNotEqual(SidebarSelection.personal, .organization("o"))
        XCTAssertEqual(SidebarSelection.personal.displayName, "Personal")

        let counts: [SidebarSelection: Int] = [.allItems: 3, .personal: 1, .organization("o"): 2]
        XCTAssertEqual(counts[.personal], 1)
        XCTAssertEqual(counts.count, 3)
    }
}
