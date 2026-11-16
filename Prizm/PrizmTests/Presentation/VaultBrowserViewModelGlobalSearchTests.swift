import XCTest
@testable import Prizm

@MainActor
final class VaultBrowserViewModelGlobalSearchTests: XCTestCase {

    private var vault: MockVaultRepository!
    private var sut: VaultBrowserViewModel!

    private let sampleLogin = VaultItem(
        id: "1", name: "GitHub", isFavorite: false, isDeleted: false,
        creationDate: .now, revisionDate: .now,
        content: .login(LoginContent(username: "alice", password: nil, uris: [], totp: nil, notes: nil, customFields: []))
    )
    private let sampleCard = VaultItem(
        id: "2", name: "Visa", isFavorite: false, isDeleted: false,
        creationDate: .now, revisionDate: .now,
        content: .card(CardContent(cardholderName: "Alice", brand: nil, number: "4111111111111111", expMonth: nil, expYear: nil, code: nil, notes: nil, customFields: []))
    )

    override func setUp() async throws {
        try await super.setUp()
        vault = MockVaultRepository()
        await vault.populate(items: [sampleLogin, sampleCard], folders: [], organizations: [], collections: [], syncedAt: .now)
        let syncRepo = MockSyncTimestampRepository(storedDate: nil)
        sut = VaultBrowserViewModel(
            vault:           vault,
            search:          SearchVaultUseCaseImpl(vault: vault),
            delete:          StubDeleteUseCase(),
            permanentDelete: StubPermanentDeleteUseCase(),
            restore:         StubRestoreUseCase(),
            createFolder:     StubCreateFolder(),
            renameFolder:     StubRenameFolder(),
            deleteFolder:     StubDeleteFolder(),
            moveItem:         StubMoveItem(),
            createCollection: StubCreateCollection(),
            renameCollection: StubRenameCollection(),
            deleteCollection: StubDeleteCollection(),
            syncTimestamp:    syncRepo,
            getLastSyncDate:  GetLastSyncDateUseCaseImpl(repository: syncRepo)
        )
    }

    // MARK: - 1.1 activateGlobalSearch stores previous selection and sets flag

    func testHistory_navigatesItemsAndClearsForwardBranch() async {
        XCTAssertFalse(sut.canGoBack)
        XCTAssertFalse(sut.canGoForward)
        sut.itemSelection = sampleLogin
        sut.itemSelection = sampleCard

        await sut.goBack()
        XCTAssertEqual(sut.itemSelection?.id, sampleLogin.id)
        XCTAssertTrue(sut.canGoForward)
        await sut.goForward()
        XCTAssertEqual(sut.itemSelection?.id, sampleCard.id)
        await sut.goBack()
        sut.sidebarSelection = .favorites
        XCTAssertFalse(sut.canGoForward)
        await sut.goBack()
        XCTAssertEqual(sut.sidebarSelection, .allItems)
        XCTAssertEqual(sut.itemSelection?.id, sampleLogin.id)
    }

    func testHistory_restoresGlobalSearchWithSelectedResult() async {
        sut.sidebarSelection = .type(.login)
        sut.activateGlobalSearch()
        sut.searchQuery = "Visa"
        sut.itemSelection = sampleCard
        sut.sidebarSelection = .allItems

        await sut.goBack()

        XCTAssertTrue(sut.isGlobalSearch)
        XCTAssertEqual(sut.searchQuery, "Visa")
        XCTAssertEqual(sut.itemSelection?.id, sampleCard.id)
    }

    func testHistory_favoriteShortcutIsOneNavigationStep() async {
        sut.sidebarSelection = .type(.card)
        sut.itemSelection = sampleCard
        sut.selectFavorite(sampleLogin)

        await sut.goBack()

        XCTAssertEqual(sut.sidebarSelection, .type(.card))
        XCTAssertEqual(sut.itemSelection?.id, sampleCard.id)
    }

    func testHistory_resetClearsSearchSelectionAndDirections() {
        sut.itemSelection = sampleLogin
        sut.activateGlobalSearch()
        sut.searchQuery = "GitHub"

        sut.resetNavigationHistory()

        XCTAssertFalse(sut.canGoBack)
        XCTAssertFalse(sut.canGoForward)
        XCTAssertFalse(sut.isGlobalSearch)
        XCTAssertNil(sut.itemSelection)
        XCTAssertEqual(sut.searchQuery, "")
    }

    func testActivateGlobalSearch_storesPreviousSelectionAndSetsFlag() {
        sut.sidebarSelection = .type(.login)
        sut.activateGlobalSearch()

        XCTAssertTrue(sut.isGlobalSearch)
        XCTAssertEqual(sut.previousSelection, .type(.login))
    }

    // MARK: - 1.2 deactivateGlobalSearch restores selection, clears query, resets flag

    func testDeactivateGlobalSearch_restoresSelectionAndClearsState() {
        sut.sidebarSelection = .favorites
        sut.activateGlobalSearch()
        sut.searchQuery = "test"

        sut.deactivateGlobalSearch()

        XCTAssertFalse(sut.isGlobalSearch)
        XCTAssertEqual(sut.searchQuery, "")
        XCTAssertEqual(sut.sidebarSelection, .favorites)
    }

    // MARK: - 1.3 search passes .allItems when isGlobalSearch is true

    func testGlobalSearch_searchesAllItems() async throws {
        sut.sidebarSelection = .type(.login)
        sut.activateGlobalSearch()
        sut.searchQuery = "Visa"

        // Yield twice: once for the outer Task spawned by searchQuery.didSet,
        // once for the inner Task spawned by refreshItems().
        await Task.yield()
        await Task.yield()

        // Visa is a Card, not a Login — should still appear in global search
        XCTAssertTrue(sut.displayedItems.contains(where: { $0.name == "Visa" }))
    }

    func testGlobalSearch_fromFolder_includesItemsOutsideFolder() async throws {
        sut.sidebarSelection = .folder("work")
        sut.activateGlobalSearch()
        sut.searchQuery = "Visa"
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(sut.displayedItems.map(\.id), [sampleCard.id])
    }

    func testFavoriteShortcut_leavesSearchAndKeepsSelectedItem() async throws {
        sut.sidebarSelection = .type(.card)
        sut.activateGlobalSearch()
        sut.searchQuery = "Visa"

        sut.selectFavorite(sampleLogin)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(sut.sidebarSelection, .allItems)
        XCTAssertEqual(sut.itemSelection?.id, sampleLogin.id)
        XCTAssertFalse(sut.isGlobalSearch)
        XCTAssertEqual(sut.searchQuery, "")
    }

    func testGlobalSearch_fromTrash_allowsCreatingAnItem() {
        sut.sidebarSelection = .trash
        sut.activateGlobalSearch()
        sut.createItemType = .login

        XCTAssertEqual(sut.createItemType, .login)
    }

    func testFavoriteShortcuts_areSortedAndExcludeTrash() async throws {
        let favorites = [("z", "Zulu", false), ("a", "Alpha", false), ("deleted", "Deleted", true)]
            .map { id, name, deleted in
                VaultItem(id: id, name: name, isFavorite: true, isDeleted: deleted,
                          creationDate: .now, revisionDate: .now, content: sampleLogin.content)
            }
        await vault.populate(items: favorites + [sampleCard], folders: [],
                             organizations: [], collections: [], syncedAt: .now)
        sut.refreshCounts()
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(sut.favoriteItems.map(\.id), ["a", "z"])
    }

    // MARK: - 1.4 sidebar selection change deactivates global search

    func testSidebarSelectionChange_deactivatesGlobalSearch() {
        sut.activateGlobalSearch()
        XCTAssertTrue(sut.isGlobalSearch)

        sut.sidebarSelection = .type(.card)

        XCTAssertFalse(sut.isGlobalSearch)
    }

    // MARK: - 1.5 escape/clear deactivates global search and restores selection

    func testDeactivateGlobalSearch_afterEscape_restoresSelection() {
        sut.sidebarSelection = .type(.identity)
        sut.activateGlobalSearch()
        sut.searchQuery = "something"

        // Simulate escape/clear
        sut.deactivateGlobalSearch()

        XCTAssertFalse(sut.isGlobalSearch)
        XCTAssertEqual(sut.sidebarSelection, .type(.identity))
        XCTAssertEqual(sut.searchQuery, "")
    }
}

// MARK: - Stub use cases (minimal, no-op)

private final class StubDeleteUseCase: DeleteVaultItemUseCase {
    func execute(id: String) async throws {}
}

private final class StubPermanentDeleteUseCase: PermanentDeleteVaultItemUseCase {
    func execute(id: String) async throws {}
}

private final class StubRestoreUseCase: RestoreVaultItemUseCase {
    func execute(id: String) async throws {}
}

private struct StubCreateFolder: CreateFolderUseCase {
    func execute(name: String) async throws -> Folder { Folder(id: "stub", name: name) }
}
private struct StubRenameFolder: RenameFolderUseCase {
    func execute(id: String, name: String) async throws -> Folder { Folder(id: id, name: name) }
}
private struct StubDeleteFolder: DeleteFolderUseCase {
    func execute(id: String) async throws {}
}
private struct StubMoveItem: MoveItemToFolderUseCase {
    func execute(itemId: String, folderId: String?) async throws {}
    func execute(itemIds: [String], folderId: String?) async throws {}
}
private struct StubCreateCollection: CreateCollectionUseCase {
    func execute(name: String, organizationId: String) async throws -> OrgCollection {
        OrgCollection(id: "stub", organizationId: organizationId, name: name)
    }
}
private struct StubRenameCollection: RenameCollectionUseCase {
    func execute(collectionId: String, name: String, organizationId: String) async throws -> OrgCollection {
        OrgCollection(id: collectionId, organizationId: organizationId, name: name)
    }
}
private struct StubDeleteCollection: DeleteCollectionUseCase {
    func execute(collectionId: String, organizationId: String) async throws {}
}
