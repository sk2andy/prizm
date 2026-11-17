import SwiftUI

// MARK: - SidebarView

/// Left-column sidebar with favorite shortcuts and native navigation sections.
///
/// Each row displays a live item count sourced from `VaultBrowserViewModel.itemCounts`.
/// The sidebar is always visible, even when a category is empty.
struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    @State private var sidebarSections: [SidebarSection] = [.menu, .types, .folders, .organizations, .trash]
    @State private var collapsedSections: Set<SidebarSection> = []
    @State private var visibleSelections: [SidebarSelection] = []
    let itemCounts: [SidebarSelection: Int]
    let folders: [Folder]
    var organizations: [Organization] = []
    var collections: [OrgCollection] = []
    var favoriteItems: [VaultItem] = []
    var faviconLoader: FaviconLoader? = nil
    var onSelectFavorite: ((VaultItem) -> Void)? = nil

    @Environment(\.colorSchemeContrast) private var contrast

    // Folder actions — provided by VaultBrowserViewModel
    var onCreateFolder: ((String) -> Void)?
    var onRenameFolder: ((String, String) -> Void)?  // (id, newName)
    var onDeleteFolder: ((Folder) -> Void)?
    var onDropItems: (([String], String) -> Void)?   // (itemIds, folderId)

    // Collection actions — provided by VaultBrowserViewModel
    var onCreateCollection: ((String, String) -> Void)?  // (name, organizationId)
    var onRenameCollection: ((String, String, String) -> Void)?  // (id, orgId, newName)
    var onDeleteCollection: ((String, String) -> Void)?  // (id, orgId)

    // Inline folder rename/create state
    @State private var renamingFolderId: String?
    @State private var renameText: String = ""
    @FocusState private var isRenameFocused: Bool

    @State private var isCreatingFolder = false
    @State private var newFolderName: String = "New Folder"
    @FocusState private var isNewFolderFocused: Bool

    // Inline collection create state: keyed by orgId
    @State private var creatingCollectionInOrg: String? = nil
    @State private var newCollectionName: String = ""
    @FocusState private var isNewCollectionFocused: Bool

    // Inline collection rename state
    @State private var renamingCollectionId: String?
    @State private var renamingCollectionOrgId: String?
    @State private var collectionRenameText: String = ""
    @FocusState private var isCollectionRenameFocused: Bool

    // Delete collection confirmation
    @State private var collectionToDelete: OrgCollection? = nil
    @State private var showDeleteCollectionAlert = false

    // Tree collapse state (per-session)
    @State private var expandedFolderIds: Set<String> = []
    @State private var expandedOrgIds: Set<String> = []

    private var folderTree: [FolderTreeNode] {
        FolderTreeNode.buildTree(from: folders)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.rowHorizontal) {
                if !favoriteItems.isEmpty {
                    favoriteShortcuts
                }
                ForEach(sidebarSections, id: \.self) { section in
                    if section != .organizations || !organizations.isEmpty {
                        if section == .menu || section == .trash {
                            VStack(spacing: 3) {
                                renderRows(for: section)
                            }
                        } else {
                            sectionCard(for: section)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.rowHorizontal)
            .padding(.vertical, Spacing.rowHorizontal)
        }
        .accessibilityIdentifier(AccessibilityID.Sidebar.list)
        .accessibilityLabel("Sidebar")
        .onPreferenceChange(SidebarRowsPreferenceKey.self) { visibleSelections = $0 }
        .onMoveCommand { direction in
            guard !isCreatingFolder, renamingFolderId == nil,
                  creatingCollectionInOrg == nil, renamingCollectionId == nil,
                  let selection, let index = visibleSelections.firstIndex(of: selection) else { return }
            let offset: Int
            switch direction {
            case .up: offset = -1
            case .down: offset = 1
            default: return
            }
            if visibleSelections.indices.contains(index + offset) {
                self.selection = visibleSelections[index + offset]
            }
        }
        .alert("Delete Collection", isPresented: $showDeleteCollectionAlert,
               presenting: collectionToDelete) { col in
            Button("Delete", role: .destructive) {
                onDeleteCollection?(col.id, col.organizationId)
            }
            Button("Cancel", role: .cancel) {}
        } message: { col in
            Text("\u{201C}\(col.name)\u{201D} will be permanently deleted. Items in this collection will remain in the vault.")
        }
    }

    // MARK: - Favorite Shortcuts

    private var favoriteShortcuts: some View {
        VStack(alignment: .leading, spacing: Spacing.headerGap) {
            Text("Favorites")
                .font(Typography.fieldLabelProminent)
                .foregroundStyle(.secondary)
            HStack(spacing: Spacing.headerGap) {
                ForEach(favoriteItems.prefix(3)) { item in
                    Button {
                        onSelectFavorite?(item)
                    } label: {
                        VStack(spacing: Spacing.headerGap) {
                            favoriteIcon(for: item)
                                .frame(width: 20, height: 20)
                            Text(item.name)
                                .font(Typography.listSubtitle)
                                .lineLimit(2, reservesSpace: true)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, Spacing.badgeHorizontal)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(.primary.opacity(Opacity.cardBorder(contrast)),
                                    in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .help(item.name)
                    .accessibilityLabel("Open \(item.name)")
                }
            }
        }
        .padding(.horizontal, Spacing.headerGap)
        .padding(.vertical, Spacing.headerGap)
    }

    @ViewBuilder
    private func favoriteIcon(for item: VaultItem) -> some View {
        if case .login(let login) = item.content, let faviconLoader {
            FaviconView(
                domain: login.uris.first.flatMap { URL(string: $0.uri)?.host },
                itemType: .login,
                loader: faviconLoader,
                size: 20
            )
        } else {
            Image(systemName: favoriteItemType(for: item).sfSymbol)
                .font(Typography.sectionHeader)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
        }
    }

    private func favoriteItemType(for item: VaultItem) -> ItemType {
        switch item.content {
        case .login: .login
        case .card: .card
        case .identity: .identity
        case .secureNote: .secureNote
        case .sshKey: .sshKey
        }
    }

    // MARK: - Grouped Navigation

    private func sectionCard(for section: SidebarSection) -> some View {
        VStack(alignment: .leading, spacing: Spacing.labelGap) {
            HStack {
                Button {
                    if collapsedSections.contains(section) {
                        collapsedSections.remove(section)
                    } else {
                        collapsedSections.insert(section)
                    }
                } label: {
                    HStack(spacing: Spacing.labelGap) {
                        Image(systemName: collapsedSections.contains(section) ? "chevron.right" : "chevron.down")
                        Text(section.title)
                        Spacer(minLength: 0)
                    }
                    .font(Typography.fieldLabelProminent)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.title)
                .accessibilityValue(collapsedSections.contains(section) ? "Collapsed" : "Expanded")
                if section == .folders {
                    Button {
                        collapsedSections.remove(.folders)
                        newFolderName = "New Folder"
                        isCreatingFolder = true
                        isNewFolderFocused = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help("New Folder")
                    .accessibilityLabel("New Folder")
                }
            }
            .padding(.horizontal, Spacing.headerGap)
            .padding(.vertical, Spacing.headerGap)
            .contextMenu {
                Button("Move Section Up") { moveSection(section, by: -1) }
                    .disabled(sidebarSections.first == section)
                Button("Move Section Down") { moveSection(section, by: 1) }
                    .disabled(sidebarSections.last == section)
            }
            if !collapsedSections.contains(section) {
                VStack(alignment: .leading, spacing: 3) {
                    renderRows(for: section)
                }
                .disclosureGroupStyle(SidebarDisclosureStyle())
            }
        }
        .padding(Spacing.labelGap)
        .background(.primary.opacity(Opacity.cardBorder(contrast)),
                    in: RoundedRectangle(cornerRadius: Spacing.contentCornerRadius))
    }

    private func moveSection(_ section: SidebarSection, by offset: Int) {
        guard let index = sidebarSections.firstIndex(of: section),
              sidebarSections.indices.contains(index + offset) else { return }
        sidebarSections.swapAt(index, index + offset)
    }

    // MARK: - Row Rendering

    @ViewBuilder
    private func renderRows(for section: SidebarSection) -> some View {
        switch section {
        case .menu:
            SidebarRowView(title: "All Items", systemImage: "square.grid.2x2", selection: .allItems, currentSelection: $selection, count: itemCounts[.allItems] ?? 0)
            SidebarRowView(title: "Favorites", systemImage: "star", selection: .favorites, currentSelection: $selection, count: itemCounts[.favorites] ?? 0)
            SidebarRowView(title: "Codes", systemImage: "clock", selection: .verificationCodes, currentSelection: $selection, count: itemCounts[.verificationCodes] ?? 0)
        case .folders:
            if isCreatingFolder {
                TextField("Name or Parent/Name", text: $newFolderName, onCommit: {
                    commitCreate()
                })
                .focused($isNewFolderFocused)
                .help("Nest a folder by adding the parent folder's name followed by a /. Example: Social/Forums")
                .onExitCommand {
                    isCreatingFolder = false
                    isNewFolderFocused = false
                }
            }
            ForEach(folderTree) { node in
                FolderTreeRow(
                    node: node,
                    selection: $selection,
                    itemCounts: itemCounts,
                    expandedIds: $expandedFolderIds,
                    renamingFolderId: $renamingFolderId,
                    renameText: $renameText,
                    isRenameFocused: $isRenameFocused,
                    onDeleteFolder: { onDeleteFolder?($0) },
                    onDropItems: { ids, fid in onDropItems?(ids, fid) },
                    onRenameFolder: { id, name in onRenameFolder?(id, name) }
                )
            }
            if folders.isEmpty && !isCreatingFolder {
                Text("No folders")
                    .font(Typography.listSubtitle)
                    .foregroundStyle(.secondary)
            }
        case .types:
            ForEach(ItemType.allCases, id: \.self) { type in
                SidebarRowView(title: type.displayName, systemImage: type.sfSymbol, selection: .type(type), currentSelection: $selection, count: itemCounts[.type(type)] ?? 0)
            }
        case .organizations:
            ForEach(organizations) { org in
                let orgCollections = collections.filter { $0.organizationId == org.id }
                OrgDisclosureRow(
                    org: org,
                    selection: $selection,
                    collections: orgCollections,
                    itemCounts: itemCounts,
                    isExpanded: Binding(
                        get: { expandedOrgIds.contains(org.id) },
                        set: { if $0 { expandedOrgIds.insert(org.id) } else { expandedOrgIds.remove(org.id) } }
                    ),
                    creatingCollectionInOrg: $creatingCollectionInOrg,
                    newCollectionName: $newCollectionName,
                    isNewCollectionFocused: $isNewCollectionFocused,
                    renamingCollectionId: $renamingCollectionId,
                    renamingCollectionOrgId: $renamingCollectionOrgId,
                    collectionRenameText: $collectionRenameText,
                    isCollectionRenameFocused: $isCollectionRenameFocused,
                    onCreateCollection: { name in onCreateCollection?(name, org.id) },
                    onRenameCollection: { colId, name in onRenameCollection?(colId, org.id, name) },
                    onDeleteCollection: { col in
                        collectionToDelete = col
                        showDeleteCollectionAlert = true
                    }
                )
            }
        case .trash:
            SidebarRowView(title: "Trash", systemImage: "trash", selection: .trash, currentSelection: $selection, count: itemCounts[.trash] ?? 0)
        }
    }

    private func commitCreate() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        isCreatingFolder = false
        isNewFolderFocused = false
        guard !trimmed.isEmpty else { return }
        onCreateFolder?(trimmed)
    }
}

// MARK: - FolderTreeRow

/// Recursive tree row: renders a DisclosureGroup for nodes with children,
/// or a plain folder row for leaf nodes.
private struct FolderTreeRow: View {
    let node: FolderTreeNode
    @Binding var selection: SidebarSelection?
    let itemCounts: [SidebarSelection: Int]
    @Binding var expandedIds: Set<String>
    @Binding var renamingFolderId: String?
    @Binding var renameText: String
    @FocusState.Binding var isRenameFocused: Bool
    var onDeleteFolder: (Folder) -> Void
    var onDropItems: ([String], String) -> Void
    var onRenameFolder: ((String, String) -> Void)?

    var body: some View {
        if node.hasChildren {
            DisclosureGroup(isExpanded: Binding(
                get: { expandedIds.contains(node.id) },
                set: { expanded in
                    if expanded { expandedIds.insert(node.id) }
                    else { expandedIds.remove(node.id) }
                }
            )) {
                ForEach(node.children) { child in
                    FolderTreeRow(
                        node: child,
                        selection: $selection,
                        itemCounts: itemCounts,
                        expandedIds: $expandedIds,
                        renamingFolderId: $renamingFolderId,
                        renameText: $renameText,
                        isRenameFocused: $isRenameFocused,
                        onDeleteFolder: onDeleteFolder,
                        onDropItems: onDropItems,
                        onRenameFolder: onRenameFolder
                    )
                }
            } label: {
                nodeLabel
            }
        } else {
            nodeLabel
                .padding(.leading, Spacing.pageMargin)
        }
    }

    @ViewBuilder
    private var nodeLabel: some View {
        if let folder = node.folder, renamingFolderId == folder.id {
            TextField("Name or Parent/Name", text: $renameText, onCommit: {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                renamingFolderId = nil
                isRenameFocused = false
                guard !trimmed.isEmpty else { return }
                let parts = folder.name.split(separator: "/").map(String.init)
                let newName = parts.count > 1
                    ? parts.dropLast().joined(separator: "/") + "/" + trimmed
                    : trimmed
                guard newName != folder.name else { return }
                onRenameFolder?(folder.id, newName)
            })
            .focused($isRenameFocused)
            .help("Nest a folder by adding the parent folder's name followed by a /. Example: Social/Forums")
            .onExitCommand {
                renamingFolderId = nil
                isRenameFocused = false
            }
        } else if let folder = node.folder {
            // Real folder — selectable, droppable
            FolderRowLabel(
                folder: folder,
                selection: $selection,
                displayName: node.name,
                count: itemCounts[.folder(folder.id)] ?? 0,
                onRename: {
                    renameText = node.name
                    renamingFolderId = folder.id
                    isRenameFocused = true
                },
                onDelete: { onDeleteFolder(folder) },
                onDrop: { ids in onDropItems(ids, folder.id) }
            )
        } else {
            // Virtual parent — not selectable, no drop, no context menu
            Label(node.name, systemImage: "folder")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - FolderRowLabel

/// Folder row with drop-target highlight and context menu.
/// Extracted to a struct so `@State var isDropTargeted` is per-row.
private struct FolderRowLabel: View {
    let folder: Folder
    @Binding var selection: SidebarSelection?
    var displayName: String? = nil
    let count: Int
    var onRename: () -> Void
    var onDelete: () -> Void
    var onDrop: ([String]) -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isDropTargeted = false

    var body: some View {
        SidebarRowView(
            title: displayName ?? folder.name,
            systemImage: "folder",
            selection: .folder(folder.id),
            currentSelection: $selection,
            count: count
        )
            .background(isDropTargeted ? Color.accentColor.opacity(Opacity.dropTarget(contrast)) : Color.clear,
                        in: RoundedRectangle(cornerRadius: Spacing.itemIconCornerRadius))
            .contextMenu {
                Button("Rename") { onRename() }
                Divider()
                Button("Delete Folder", role: .destructive) { onDelete() }
            }
            .dropDestination(for: String.self) { itemIds, _ in
                guard !itemIds.isEmpty else { return false }
                onDrop(itemIds)
                return true
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }
    }
}

// MARK: - SidebarSection

enum SidebarSection: String, CaseIterable {
    case menu, folders, types, organizations, trash
    var title: String { self.rawValue.capitalized }
}

// MARK: - OrgDisclosureRow

/// Renders one organization as a DisclosureGroup with its collection rows as children.
/// The header optionally shows a `+` button when the user can manage collections.
private struct OrgDisclosureRow: View {
    let org: Organization
    @Binding var selection: SidebarSelection?
    let collections: [OrgCollection]
    let itemCounts: [SidebarSelection: Int]
    @Binding var isExpanded: Bool

    // Inline collection create state
    @Binding var creatingCollectionInOrg: String?
    @Binding var newCollectionName: String
    @FocusState.Binding var isNewCollectionFocused: Bool

    // Inline collection rename state
    @Binding var renamingCollectionId: String?
    @Binding var renamingCollectionOrgId: String?
    @Binding var collectionRenameText: String
    @FocusState.Binding var isCollectionRenameFocused: Bool

    var onCreateCollection: (String) -> Void
    var onRenameCollection: (String, String) -> Void   // (collectionId, newName)
    var onDeleteCollection: (OrgCollection) -> Void

    private var collectionTree: [CollectionTreeNode] {
        CollectionTreeNode.buildTree(from: collections)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            // Inline new-collection TextField (matching folder create pattern)
            if creatingCollectionInOrg == org.id {
                TextField("Collection name", text: $newCollectionName, onCommit: {
                    commitCreate()
                })
                .focused($isNewCollectionFocused)
                .onExitCommand {
                    creatingCollectionInOrg = nil
                    newCollectionName = ""
                }
            }

            ForEach(collectionTree) { node in
                CollectionTreeRow(
                    node: node,
                    org: org,
                    selection: $selection,
                    itemCounts: itemCounts,
                    renamingCollectionId: $renamingCollectionId,
                    renamingCollectionOrgId: $renamingCollectionOrgId,
                    collectionRenameText: $collectionRenameText,
                    isCollectionRenameFocused: $isCollectionRenameFocused,
                    onRenameCollection: onRenameCollection,
                    onDeleteCollection: onDeleteCollection
                )
            }

            if collections.isEmpty && creatingCollectionInOrg != org.id {
                Text("No collections")
                    .font(Typography.listSubtitle)
                    .foregroundStyle(.secondary)
            }
        } label: {
            orgHeader
        }
    }

    @ViewBuilder
    private var orgHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            SidebarRowView(
                title: org.name,
                systemImage: "building.2",
                selection: .organization(org.id),
                currentSelection: $selection,
                count: itemCounts[.organization(org.id)] ?? 0
            )
            if org.canManageCollections {
                Button {
                    newCollectionName = ""
                    creatingCollectionInOrg = org.id
                    isExpanded = true
                    isNewCollectionFocused = true
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                }
                .buttonStyle(.plain)
                .help("New Collection")
                .accessibilityLabel("New Collection")
                .padding(.trailing, 2)
                .offset(y: -4)
            }
        }
    }

    private func commitCreate() {
        let trimmed = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        creatingCollectionInOrg = nil
        newCollectionName = ""
        guard !trimmed.isEmpty else { return }
        onCreateCollection(trimmed)
    }
}

// MARK: - CollectionTreeRow

/// Recursive tree row for collections: renders a DisclosureGroup for nodes with children,
/// or a plain collection row for leaf nodes. Mirrors `FolderTreeRow`.
private struct CollectionTreeRow: View {
    let node: CollectionTreeNode
    let org: Organization
    @Binding var selection: SidebarSelection?
    let itemCounts: [SidebarSelection: Int]
    @Binding var renamingCollectionId: String?
    @Binding var renamingCollectionOrgId: String?
    @Binding var collectionRenameText: String
    @FocusState.Binding var isCollectionRenameFocused: Bool
    var onRenameCollection: (String, String) -> Void   // (collectionId, newName)
    var onDeleteCollection: (OrgCollection) -> Void

    @State private var isExpanded = false

    var body: some View {
        if node.hasChildren {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(node.children) { child in
                    CollectionTreeRow(
                        node: child,
                        org: org,
                        selection: $selection,
                        itemCounts: itemCounts,
                        renamingCollectionId: $renamingCollectionId,
                        renamingCollectionOrgId: $renamingCollectionOrgId,
                        collectionRenameText: $collectionRenameText,
                        isCollectionRenameFocused: $isCollectionRenameFocused,
                        onRenameCollection: onRenameCollection,
                        onDeleteCollection: onDeleteCollection
                    )
                }
            } label: {
                nodeLabel
            }
        } else {
            nodeLabel
                .padding(.leading, Spacing.pageMargin)
        }
    }

    @ViewBuilder
    private var nodeLabel: some View {
        if let col = node.collection,
           renamingCollectionId == col.id && renamingCollectionOrgId == col.organizationId {
            TextField("Collection name", text: $collectionRenameText, onCommit: {
                let trimmed = collectionRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
                renamingCollectionId    = nil
                renamingCollectionOrgId = nil
                isCollectionRenameFocused = false
                guard !trimmed.isEmpty, trimmed != col.name else { return }
                onRenameCollection(col.id, trimmed)
            })
            .focused($isCollectionRenameFocused)
            .onExitCommand {
                renamingCollectionId    = nil
                renamingCollectionOrgId = nil
                isCollectionRenameFocused = false
            }
        } else if let col = node.collection {
            SidebarRowView(
                title: node.name,
                systemImage: "tray.2",
                selection: .collection(col.id),
                currentSelection: $selection,
                count: itemCounts[.collection(col.id)] ?? 0
            )
                .contextMenu {
                    if org.canManageCollections {
                        Button("Rename") {
                            collectionRenameText    = col.name
                            renamingCollectionId    = col.id
                            renamingCollectionOrgId = col.organizationId
                            isCollectionRenameFocused = true
                        }
                        Divider()
                        Button("Delete Collection", role: .destructive) {
                            onDeleteCollection(col)
                        }
                    }
                }
        } else {
            // Virtual parent node — not selectable, no context menu
            Label(node.name, systemImage: "tray.2")
                .foregroundStyle(.secondary)
        }
    }
}

/// Keep tree disclosure arrows inside the card and match section-header chevrons.
private struct SidebarDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: Spacing.labelGap) {
            HStack(spacing: 0) {
                Button {
                    optionalAnimation(.easeInOut(duration: 0.18)) {
                        configuration.isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(Typography.fieldLabelProminent)
                        .foregroundStyle(.secondary)
                        .frame(width: 12, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(configuration.isExpanded ? "Collapse group" : "Expand group")
                .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
                .padding(.leading, Spacing.headerGap)
                configuration.label
            }
            if configuration.isExpanded {
                configuration.content
                    .padding(.leading, Spacing.pageMargin)
            }
        }
    }
}

// MARK: - SidebarRowView

private struct SidebarRowView: View {
    let title: String
    let systemImage: String
    let selection: SidebarSelection
    @Binding var currentSelection: SidebarSelection?
    let count: Int

    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button {
            currentSelection = selection
            isFocused = true
        } label: {
            HStack(spacing: Spacing.headerGap) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(title)
                    .fontWeight(currentSelection == selection ? .semibold : .regular)
                    .lineLimit(1)
                Spacer(minLength: Spacing.labelGap)
                Text(count.formatted())
                    .font(Typography.listSubtitle)
                    .foregroundStyle(.secondary)
            }
            .font(Typography.sidebarRow)
            .padding(.horizontal, Spacing.rowHorizontal)
            .padding(.vertical, Spacing.rowVertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(currentSelection == selection
                        ? Opacity.dropTarget(contrast)
                        : isHovered ? Opacity.cardBorder(contrast) : 0),
                        in: RoundedRectangle(cornerRadius: Spacing.itemIconCornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: Spacing.itemIconCornerRadius))
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($isFocused)
        .onChange(of: currentSelection) { _, newSelection in
            if newSelection == selection { isFocused = true }
        }
        .onHover { isHovered = $0 }
        .help(title)
        .preference(key: SidebarRowsPreferenceKey.self, value: [selection])
        .accessibilityLabel(title)
        .accessibilityValue("\(count) items")
        .accessibilityAddTraits(currentSelection == selection ? .isSelected : [])
        .accessibilityIdentifier(accessibilityID)
    }

    private var accessibilityID: String {
        switch selection {
        case .personal: "sidebar.personal"
        case .allItems: AccessibilityID.Sidebar.allItems
        case .favorites: AccessibilityID.Sidebar.favorites
        case .verificationCodes: "sidebar.codes"
        case .trash: AccessibilityID.Sidebar.trash
        case .type(let type): AccessibilityID.Sidebar.type(type.rawValue)
        case .folder(let id): "sidebar.folder.\(id)"
        case .organization(let id): "sidebar.organization.\(id)"
        case .collection(let id): "sidebar.collection.\(id)"
        case .newFolder: "sidebar.newFolder"
        case .newCollection(let id): "sidebar.newCollection.\(id)"
        }
    }
}

nonisolated private struct SidebarRowsPreferenceKey: PreferenceKey {
    static var defaultValue: [SidebarSelection] { [] }

    static func reduce(value: inout [SidebarSelection], nextValue: () -> [SidebarSelection]) {
        value.append(contentsOf: nextValue())
    }
}
