import SwiftUI
import os.log

// MARK: - VaultBrowserView

/// Three resizable panes with a shared tinted sidebar and an inset content surface.
///
/// - Sidebar:  `SidebarView` (categories + counts)
/// - Content:  `ItemListView` with inline native vault search and `+` button
/// - Detail:   `ItemDetailView` with Edit / Delete buttons
struct VaultBrowserView: View {

    @ObservedObject var viewModel: VaultBrowserViewModel
    let faviconLoader: FaviconLoader
    var accountLabel: String = "Vault unlocked"
    let makeEditViewModel: (VaultItem) -> ItemEditViewModel
    let makeCreateViewModel: (ItemType, String?) -> ItemEditViewModel
    /// Factory for creating `AttachmentAddViewModel` — injected from AppContainer to
    /// keep the Presentation layer decoupled from the Data layer (Constitution §II).
    var makeAddAttachmentViewModel: ((String) -> AttachmentAddViewModel)? = nil
    /// Factory for creating `AttachmentBatchViewModel` — injected from AppContainer.
    var makeBatchAttachmentViewModel: ((String) -> AttachmentBatchViewModel)? = nil
    /// Factory for `AttachmentRowViewModel` — injected from AppContainer.
    var makeAttachmentRowViewModel: ((String, Attachment) -> AttachmentRowViewModel)? = nil
    /// Factory for the TOTP code tracker — injected from AppContainer (Constitution §II).
    var makeCodesViewModel: (() -> TOTPCodesViewModel)? = nil

    @State private var showPermanentDeleteAlert = false
    @State private var showDeleteFolderAlert = false
    @State private var folderToDelete: Folder?
    @State private var isSearchFieldFocused = false
    @State private var isSidebarVisible = true
    @Environment(\.colorSchemeContrast) private var contrast

    private let logger = Logger(subsystem: "com.prizm", category: "UI.VaultBrowser")

    private var listMinimumWidth: CGFloat {
        viewModel.sidebarSelection == .verificationCodes && !viewModel.isGlobalSearch
            ? Spacing.codesListMinimumWidth : Spacing.itemListMinimumWidth
    }

    private var minimumWindowWidth: CGFloat {
        listMinimumWidth + Spacing.detailMinimumWidth + (isSidebarVisible ? Spacing.sidebarMinimumWidth : 0)
            + Spacing.headerGap * 2 + (isSidebarVisible ? 2 : 1)
    }

    /// The middle column: Trash, Verification Codes, or the regular item list.
    /// Extracted from `body` to keep the type checker fast.
    @ViewBuilder
    private var itemListPane: some View {
        if viewModel.sidebarSelection == .trash && !viewModel.isGlobalSearch {
            TrashView(
                items:             viewModel.displayedItems,
                selection:         $viewModel.itemSelection,
                faviconLoader:     faviconLoader,
                onRestore:         { id in await viewModel.performRestore(id: id) },
                onPermanentDelete: { id in await viewModel.performPermanentDelete(id: id) }
            )
        } else if viewModel.sidebarSelection == .verificationCodes && !viewModel.isGlobalSearch, let makeCodesViewModel {
            VerificationCodesListView(
                items:         viewModel.displayedItems,
                selection:     $viewModel.itemSelection,
                faviconLoader: faviconLoader,
                searchQuery:   viewModel.searchQuery.isEmpty ? nil : viewModel.searchQuery,
                makeViewModel: makeCodesViewModel,
                onCopy:        { viewModel.copy($0) }
            )
        } else {
            ItemListView(
                items:          viewModel.displayedItems,
                selection:      $viewModel.itemSelection,
                faviconLoader:  faviconLoader,
                searchQuery:    viewModel.searchQuery.isEmpty ? nil : viewModel.searchQuery,
                organizations:  viewModel.organizations,
                onDelete:       { id in await viewModel.performSoftDelete(id: id) },
                onToggleFavorite: { viewModel.toggleFavorite(item: $0) }
            )
        }
    }

    /// The detail column. Extracted from `body` to keep the type checker fast.
    private var itemDetail: some View {
        ItemDetailView(
            item:                           viewModel.itemSelection,
            faviconLoader:                  faviconLoader,
            folders:                        viewModel.folders,
            organizations:                  viewModel.organizations,
            onCopy:                         { viewModel.copy($0) },
            makeEditViewModel:              makeEditViewModel,
            makeAddAttachmentViewModel:     makeAddAttachmentViewModel,
            makeBatchAttachmentViewModel:   makeBatchAttachmentViewModel,
            makeAttachmentRowViewModel:     makeAttachmentRowViewModel,
            onAttachmentsChanged:           { viewModel.refreshItemSelection() },
            onEditSheetChanged:             { viewModel.handleEditSheetState($0) },
            onSoftDelete:                   { id in await viewModel.performSoftDelete(id: id) },
            onRestore:                      { id in await viewModel.performRestore(id: id) },
            onPermanentDelete:              { id in await viewModel.performPermanentDelete(id: id) },
            makeCodesViewModel:             makeCodesViewModel,
            editTrigger:                    viewModel.editTrigger,
            saveTrigger:                    viewModel.saveTrigger,
            headerActions:                  { detailActions }
        )
    }

    private var listTitle: String {
        if viewModel.isGlobalSearch { return "Search Results" }
        switch viewModel.sidebarSelection {
        case .folder(let id): return viewModel.folders.first { $0.id == id }?.name ?? "Folder"
        case .organization(let id): return viewModel.organizations.first { $0.id == id }?.name ?? "Organization"
        case .collection(let id): return viewModel.collections.first { $0.id == id }?.name ?? "Collection"
        default: return viewModel.sidebarSelection.displayName
        }
    }

    private var windowNavigation: some View {
        HStack(spacing: Spacing.headerGap) {
            Button { isSidebarVisible.toggle() } label: {
                Image(systemName: "sidebar.left")
            }
            .keyboardShortcut("b", modifiers: .command)
            .help(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
            .accessibilityLabel(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
            .accessibilityIdentifier("vault.toggleSidebar")
            Spacer(minLength: 0)
            Button { Task { await viewModel.goBack() } } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!viewModel.canGoBack)
            .keyboardShortcut("[", modifiers: .command)
            .help("Back")
            .accessibilityLabel("Back")
            .accessibilityIdentifier("vault.back")
            Button { Task { await viewModel.goForward() } } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!viewModel.canGoForward)
            .keyboardShortcut("]", modifiers: .command)
            .help("Forward")
            .accessibilityLabel("Forward")
            .accessibilityIdentifier("vault.forward")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.leading, 92) // Space for the native window controls.
        .padding(.trailing, Spacing.headerGap)
        .frame(height: 30)
        .offset(y: -9) // Align with the native window buttons, centered 22pt from the top.
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            windowNavigation
            SidebarView(
                selection: Binding(
                    get: { viewModel.isGlobalSearch ? nil : viewModel.sidebarSelection },
                    set: { newValue in
                        if let value = newValue {
                            Task { @MainActor in
                                viewModel.deactivateGlobalSearch(restoreSelection: false)
                                viewModel.sidebarSelection = value
                            }
                        }
                    }
                ),
                itemCounts: viewModel.itemCounts,
                folders: viewModel.folders,
                organizations: viewModel.organizations,
                collections: viewModel.collections,
                favoriteItems: viewModel.favoriteItems,
                faviconLoader: faviconLoader,
                onSelectFavorite: { viewModel.selectFavorite($0) },
                onCreateFolder: { name in viewModel.createFolder(name: name) },
                onRenameFolder: { id, name in viewModel.renameFolder(id: id, name: name) },
                onDeleteFolder: { folder in
                    folderToDelete = folder
                    showDeleteFolderAlert = true
                },
                onDropItems: { ids, folderId in viewModel.moveItemsToFolder(itemIds: ids, folderId: folderId) },
                onCreateCollection: { name, orgId in viewModel.createCollection(name: name, organizationId: orgId) },
                onRenameCollection: { id, orgId, name in viewModel.renameCollection(id: id, organizationId: orgId, name: name) },
                onDeleteCollection: { id, orgId in viewModel.deleteCollection(id: id, organizationId: orgId) }
            )
            sidebarFooter
        }
        .frame(minWidth: Spacing.sidebarMinimumWidth, maxWidth: .infinity)
    }

    private var sidebarFooter: some View {
        VStack(spacing: Spacing.rowHorizontal) {
            HStack(spacing: Spacing.labelGap) {
                scopeButton("Personal", symbol: "house", selection: .personal)
                if viewModel.organizations.count == 1, let organization = viewModel.organizations.first {
                    scopeButton(organization.name, symbol: "briefcase", selection: .organization(organization.id))
                } else if !viewModel.organizations.isEmpty {
                    Menu {
                        ForEach(viewModel.organizations) { organization in
                            Button(organization.name) {
                                viewModel.deactivateGlobalSearch(restoreSelection: false)
                                viewModel.sidebarSelection = .organization(organization.id)
                            }
                        }
                    } label: { Label("Organizations", systemImage: "briefcase") }
                    .menuStyle(.borderlessButton)
                }
            }
            .padding(Spacing.labelGap)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: Spacing.contentCornerRadius))
            Divider()
            HStack(spacing: Spacing.headerGap) {
                Text(String(accountLabel.prefix(2)).uppercased())
                    .font(Typography.listSubtitle.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.08), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.labelGap) {
                    Text(accountLabel)
                        .font(Typography.listTitle)
                        .lineLimit(1)
                        .help(accountLabel)
                    Text(viewModel.syncStatusLabel)
                        .font(Typography.listSubtitle)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(AccessibilityID.Vault.syncStatusLabel)
                }
                Spacer(minLength: 0)
                SettingsLink { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier(AccessibilityID.Vault.settingsButton)
            }
        }
        .padding(.horizontal, Spacing.rowHorizontal)
        .padding(.vertical, Spacing.sidebarStatusBottom)
    }

    private func scopeButton(_ title: String, symbol: String, selection: SidebarSelection) -> some View {
        Button {
            viewModel.deactivateGlobalSearch(restoreSelection: false)
            viewModel.sidebarSelection = selection
        } label: {
            Label(title, systemImage: symbol)
                .font(Typography.listSubtitle)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.rowVertical)
                .background(viewModel.sidebarSelection == selection && !viewModel.isGlobalSearch
                            ? Color.primary.opacity(0.1) : Color.clear,
                            in: RoundedRectangle(cornerRadius: Spacing.headerGap))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityValue(viewModel.sidebarSelection == selection && !viewModel.isGlobalSearch
                            ? "Selected" : "Not selected")
    }

    private var listHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.headerGap) {
            HStack {
                Text(listTitle)
                    .font(Typography.sectionHeader.weight(.semibold))
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("vault.listTitle")
                Spacer()
                Menu {
                    ForEach(ItemType.allCases) { type in
                        Button { viewModel.createItemType = type } label: {
                            Label(type.displayName, systemImage: type.sfSymbol)
                        }
                    }
                } label: { Image(systemName: "plus") }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("New Item (⌘N)")
                .accessibilityLabel("New Item")
                .accessibilityIdentifier(AccessibilityID.Create.newItemButton)
                .background {
                    Button("") { viewModel.createItemType = .login }
                        .keyboardShortcut("n", modifiers: .command)
                        .frame(width: 0, height: 0)
                        .opacity(0)
                }
            }
            HStack(spacing: Spacing.labelGap) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VaultSearchField(text: Binding(
                    get: { viewModel.searchQuery },
                    set: { query in
                        if !query.isEmpty { viewModel.activateGlobalSearch() }
                        viewModel.searchQuery = query
                    }
                ), isFocused: $isSearchFieldFocused, onCancel: {
                    viewModel.deactivateGlobalSearch()
                    isSearchFieldFocused = false
                })
            }
            .padding(.horizontal, Spacing.headerGap)
            .frame(height: 36)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: Spacing.contentCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Spacing.contentCornerRadius)
                    .strokeBorder(isSearchFieldFocused ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.1))
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, Spacing.pageMargin)
        .padding(.bottom, Spacing.headerGap)
    }

    private var detailActions: some View {
        HStack(spacing: Spacing.rowHorizontal) {
            if let item = viewModel.itemSelection {
                if item.isDeleted {
                    Button("Restore") { Task { await viewModel.performRestore(id: item.id) } }
                        .accessibilityIdentifier(AccessibilityID.Trash.restoreButton)
                    Button("Delete Permanently", role: .destructive) { showPermanentDeleteAlert = true }
                        .foregroundStyle(.red)
                        .accessibilityIdentifier(AccessibilityID.Trash.permanentDeleteButton)
                } else {
                    Button { viewModel.toggleFavorite(item: item) } label: {
                        Image(systemName: item.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(item.isFavorite ? "Unfavorite" : "Favorite")
                    .accessibilityLabel(item.isFavorite ? "Unfavorite" : "Favorite")
                    .accessibilityValue(item.isFavorite ? "Favorited" : "Not favorited")
                    Button { viewModel.triggerEdit() } label: {
                        Image(systemName: "pencil")
                    }
                        .buttonStyle(.plain)
                        .help("Edit (⌘E)")
                        .accessibilityLabel("Edit")
                        .disabled(viewModel.editSheetOpen)
                        .keyboardShortcut("e", modifiers: .command)
                        .accessibilityIdentifier(AccessibilityID.Edit.editButton)
                }
            }
        }
    }

    private var browserPanes: some View {
        VaultSplitView(isSidebarVisible: isSidebarVisible, listMinimum: listMinimumWidth) {
            sidebar.padding(.top, Spacing.headerGap)
        } content: {
            VStack(spacing: 0) {
                if !isSidebarVisible { windowNavigation }
                listHeader
                syncErrorBanner
                itemListPane
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, Spacing.headerGap)
            .background(Color("CardBackground"))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: Spacing.contentCornerRadius,
                                             bottomLeadingRadius: Spacing.contentCornerRadius))
        } detail: {
            itemDetail
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, Spacing.headerGap)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: Spacing.contentCornerRadius,
                                             topTrailingRadius: Spacing.contentCornerRadius))
        }
        .padding(Spacing.headerGap)
        .background { sidebarBackground.ignoresSafeArea() }
        .frame(minWidth: minimumWindowWidth, maxWidth: .infinity, minHeight: 620, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .top)
    }

    private var sidebarBackground: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.12), Color.teal.opacity(0.07)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .background(Color(nsColor: .windowBackgroundColor))
    }

    var body: some View {
        browserPanes
        .alert("Action Failed", isPresented: Binding(
            get:  { viewModel.actionError != nil },
            set:  { if !$0 { viewModel.actionError = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.actionError = nil }
        } message: {
            Text(viewModel.actionError ?? "")
        }
        .alert("Delete Permanently?", isPresented: $showPermanentDeleteAlert) {
            Button("Delete Permanently", role: .destructive) {
                if let item = viewModel.itemSelection {
                    Task { await viewModel.performPermanentDelete(id: item.id) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(viewModel.itemSelection?.name ?? "")\" will be permanently deleted and cannot be recovered.")
        }
        .alert("Delete Folder?", isPresented: $showDeleteFolderAlert) {
            Button("Delete Folder", role: .destructive) {
                if let folder = folderToDelete {
                    viewModel.deleteFolder(id: folder.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Items in \"\(folderToDelete?.name ?? "")\" will not be deleted. They will become unfoldered.")
        }
        .accessibilityIdentifier(AccessibilityID.Vault.navigationSplit)
        .onChange(of: viewModel.sidebarSelection) { _, newValue in
            if newValue == .trash && !viewModel.isGlobalSearch {
                viewModel.searchQuery = ""
            }
        }
        .onChange(of: viewModel.searchQuery) { _, newValue in
            if newValue.isEmpty && viewModel.isGlobalSearch {
                viewModel.deactivateGlobalSearch()
            }
        }
        .onChange(of: viewModel.isGlobalSearch) { _, isActive in
            if !isActive { isSearchFieldFocused = false }
        }
        .onChange(of: viewModel.searchTrigger) { _, _ in
            isSearchFieldFocused = true
        }
        .onChange(of: viewModel.syncErrorMessage) { _, newMessage in
            if let message = newMessage {
                AccessibilityNotification.Announcement(message).post()
            }
        }
        .onChange(of: viewModel.actionError) { _, newError in
            if let error = newError {
                AccessibilityNotification.Announcement(error).post()
            }
        }
        .sheet(item: $viewModel.createItemType) { type in
            ItemEditView(
                viewModel: makeCreateViewModel(type,
                    viewModel.selectedCollectionId ?? viewModel.selectedFolderId),
                isPresented: Binding(
                    get: { viewModel.createItemType != nil },
                    set: { if !$0 { viewModel.createItemType = nil } }
                )
            )
        }
    }

    // MARK: - Sync Error Banner

    @ViewBuilder
    private var syncErrorBanner: some View {
        if let message = viewModel.syncErrorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(Typography.bannerText)
                Spacer()
                Button {
                    viewModel.dismissSyncError()
                } label: {
                    Image(systemName: "xmark")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
                .accessibilityLabel("Dismiss")
                .accessibilityIdentifier(AccessibilityID.Vault.syncErrorDismiss)
            }
            .padding(.horizontal, Spacing.bannerHorizontal)
            .padding(.vertical, Spacing.bannerVertical)
            .background(Color.yellow.opacity(Opacity.bannerBackground(contrast)))
            .frame(maxHeight: 44)
            .accessibilityIdentifier(AccessibilityID.Vault.syncErrorBanner)
        }
    }
}

/// Native split items enforce each pane's minimum while hosting edge-to-edge content.
private struct VaultSplitView<Sidebar: View, Content: View, Detail: View>: NSViewControllerRepresentable {
    let isSidebarVisible: Bool
    let listMinimum: CGFloat
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var content: () -> Content
    @ViewBuilder var detail: () -> Detail

    func makeNSViewController(context: Context) -> NSSplitViewController {
        let controller = VaultSplitViewController()
        controller.splitView = BorderlessSplitView()
        controller.splitView.isVertical = true
        controller.splitView.dividerStyle = .thin
        let sidebarItem = splitItem(sidebar(), minimum: Spacing.sidebarMinimumWidth)
        sidebarItem.canCollapse = true
        // Preserve these widths on window resize, but yield to divider drags (priority 490).
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 260)
        controller.addSplitViewItem(sidebarItem)
        let listItem = splitItem(content(), minimum: listMinimum)
        listItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 260)
        controller.addSplitViewItem(listItem)
        controller.addSplitViewItem(splitItem(detail(), minimum: Spacing.detailMinimumWidth))
        sidebarItem.isCollapsed = !isSidebarVisible
        return controller
    }

    private func splitItem<V: View>(_ view: V, minimum: CGFloat) -> NSSplitViewItem {
        let host = NSHostingController(rootView: view)
        host.safeAreaRegions = []
        host.sizingOptions = []
        let item = NSSplitViewItem(viewController: host)
        item.minimumThickness = minimum
        return item
    }

    func updateNSViewController(_ controller: NSSplitViewController, context: Context) {
        let items = controller.splitViewItems
        (items[0].viewController as? NSHostingController<Sidebar>)?.rootView = sidebar()
        (items[1].viewController as? NSHostingController<Content>)?.rootView = content()
        (items[2].viewController as? NSHostingController<Detail>)?.rootView = detail()
        items[1].minimumThickness = listMinimum
        if items[0].isCollapsed == isSidebarVisible {
            if AccessibilityInfo.prefersReducedMotion {
                items[0].isCollapsed = !isSidebarVisible
            } else {
                NSAnimationContext.runAnimationGroup { animation in
                    animation.duration = 0.22
                    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    items[0].animator().isCollapsed = !isSidebarVisible
                }
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsViewController: NSSplitViewController,
                     context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? listMinimum + Spacing.detailMinimumWidth
                   + (isSidebarVisible ? Spacing.sidebarMinimumWidth + 2 : 1),
               height: proposal.height ?? 620)
    }

    private final class BorderlessSplitView: NSSplitView {
        override func drawDivider(in rect: NSRect) {}
        nonisolated deinit {}
    }

    private final class VaultSplitViewController: NSSplitViewController {
        private var nativeTitlebarHeight: CGFloat?
        private var nativeCloseButtonX: CGFloat?

        override func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect,
                                forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
            proposedEffectiveRect.insetBy(dx: -4, dy: 0)
        }

        override func viewDidLayout() {
            super.viewDidLayout()
            positionTitlebar(extraHeight: Spacing.headerGap)
        }

        override func viewWillDisappear() {
            positionTitlebar(extraHeight: 0)
            super.viewWillDisappear()
        }

        private func positionTitlebar(extraHeight: CGFloat) {
            guard let window = view.window,
                  let closeButton = window.standardWindowButton(.closeButton),
                  let titlebar = closeButton.superview?.superview,
                  let parent = titlebar.superview else { return }
            let nativeHeight = nativeTitlebarHeight ?? titlebar.frame.height
            nativeTitlebarHeight = nativeHeight
            // Grow downward so the native buttons stay clickable and the top edge stays covered.
            // shortcut: AppKit titlebar ancestry; revisit when adopting a different window style.
            var frame = titlebar.frame
            frame.size.height = nativeHeight + extraHeight
            frame.origin.y = parent.bounds.maxY - frame.height
            titlebar.frame = frame

            let nativeX = nativeCloseButtonX ?? closeButton.frame.minX
            nativeCloseButtonX = nativeX
            let offset = (extraHeight > 0 ? Spacing.pageMargin : nativeX) - closeButton.frame.minX
            for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                guard let button = window.standardWindowButton(type) else { continue }
                button.setFrameOrigin(NSPoint(x: button.frame.minX + offset, y: button.frame.minY))
            }
        }

        nonisolated deinit {}
    }
}

/// SwiftUI's macOS search placement is toolbar-only; NSSearchField keeps native
/// search/cancel behavior while placing the control directly above its results.
private struct VaultSearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        (field.cell as? NSSearchFieldCell)?.searchButtonCell = nil
        field.isEditable = true
        field.isSelectable = true
        field.placeholderString = "Search vault"
        field.sendsSearchStringImmediately = true
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14, weight: .medium)
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Search entire vault")
        field.setAccessibilityIdentifier("vault.search")
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if isFocused, field.currentEditor() == nil {
            field.window?.makeFirstResponder(field)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: VaultSearchField

        init(_ parent: VaultSearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            parent.onCancel()
            control.window?.makeFirstResponder(nil)
            return true
        }

        // Avoid Swift 6.2's isolated-deinit runtime path on macOS 15.
        nonisolated deinit {}
    }
}
