import SwiftUI

struct ManageView: View {
    @ObservedObject var store: LibraryStore
    @StateObject private var state = ManageState()
    @Environment(\.undoManager) private var undoManager

    /// Column titles over the list, like the header of a Finder list view. The widths match NodeRow.
    private func header(pathWidth: CGFloat) -> some View {
        HStack(spacing: 12) {
            columnTitle("Name", .name)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 34)
            columnTitle("Shortcut", .shortcut)
                .frame(width: NodeRow.shortcutWidth, alignment: .leading)
            columnTitle("Path", .path)
                .frame(width: pathWidth, alignment: .leading)
            sortMenu
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    /// The sort menu at the end of the header: your order, Name, Path, Most Used, and Recently Opened. The columns
    /// also sort by a click, so the menu adds the two orders that have no column.
    private var sortMenu: some View {
        Menu {
            Picker(selection: Binding(get: { state.sortKey }, set: { state.chooseSort($0) })) {
                Text("Your Order", bundle: L10n.bundle).tag(ManageState.SortKey?.none)
                Text("Name", bundle: L10n.bundle).tag(ManageState.SortKey?.some(.name))
                Text("Path", bundle: L10n.bundle).tag(ManageState.SortKey?.some(.path))
                Text("Most Used", bundle: L10n.bundle).tag(ManageState.SortKey?.some(.mostUsed))
                Text("Recently Opened", bundle: L10n.bundle).tag(ManageState.SortKey?.some(.recentlyOpened))
            } label: {
                Text("Sort", bundle: L10n.bundle)
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text("Sort", bundle: L10n.bundle))
        .help(Text("Sort", bundle: L10n.bundle))
    }

    /// A header you can click to sort by that column, with an arrow on the column in use.
    private func columnTitle(_ title: String, _ key: ManageState.SortKey) -> some View {
        Button {
            state.toggleSort(key)
        } label: {
            HStack(spacing: 4) {
                Text(title)
                if state.sortKey == key {
                    Image(systemName: state.ascending ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort by \(title)")
    }

    /// The one share URL for a single selected item, or nil.
    private var singleShareURL: URL? {
        guard state.selection.count == 1, let id = state.selection.first else { return nil }
        return store.nodes.node(withID: id)?.shareURL
    }

    /// The nodes in the order the window shows them: yours, or sorted by a column at every level, folders first.
    private func displayed(_ nodes: [LibraryItem]) -> [LibraryItem] {
        guard let key = state.sortKey else { return nodes }
        func value(_ node: LibraryItem) -> String {
            switch key {
            case .name, .mostUsed, .recentlyOpened: return node.name
            case .shortcut: return node.shortcuts?.first?.description ?? "\u{10FFFF}"
            case .path: return node.url ?? node.command ?? node.appPath ?? ""
            }
        }
        var result = nodes.map { node -> LibraryItem in
            var node = node
            node.children = node.children.map(displayed)
            return node
        }
        if key == .mostUsed || key == .recentlyOpened {
            // Folders keep their places first, as they do in the other orders. Items are ordered by their use.
            let folders = result.filter(\.isFolder)
            let items = result.filter { !$0.isFolder }
            let ordered = key == .mostUsed
                ? UsageOrder.mostUsed(items, counts: store.openCounts)
                : UsageOrder.recentlyOpened(items, opened: store.lastOpened)
            return folders + ordered
        }
        result.sort { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            let order = value(a).localizedCaseInsensitiveCompare(value(b))
            return state.ascending ? order == .orderedAscending : order == .orderedDescending
        }
        return result
    }

    var body: some View {
        // The Path column takes about two fifths of the window, so widening the window gives it room.
        GeometryReader { geometry in
            let pathWidth = max(200, min(geometry.size.width * 0.38, 520))
            VStack(spacing: 0) {
                header(pathWidth: pathWidth)
                Divider()
                list(pathWidth: pathWidth)
                if let status = store.syncState {
                    // The iCloud state, as Finder shows it for an iCloud Drive file. It is not a dialog.
                    Divider()
                    HStack {
                        Text(status.label)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                }
            }
            // The footer is only read when VoiceOver reaches it, so a change is announced as it happens.
            .onChange(of: store.syncState) { _, state in
                if let state { AccessibilityNotification.Announcement(state.label).post() }
            }
        }
        .frame(minWidth: 680, idealWidth: 780, minHeight: 320, idealHeight: 420)
        // Remembers the window's size and position across launches.
        .background(WindowFrameAutosave(name: "ManageWindow"))
        .onAppear { store.refreshSyncState() }
    }

    /// The Reading List when it has items, then the library rows, then Recently Deleted when it has items.
    @ViewBuilder
    private func rows(_ library: [LibraryItem], reading: [LibraryItem], trashed: [LibraryItem], pathWidth: CGFloat) -> some View {
        if !reading.isEmpty {
            Section {
                // The same items as the library rows below, so each row gets its own identity.
                ForEach(reading.map(ReadingRow.init)) { row in
                    NodeRow(pathWidth: pathWidth, node: row.node, store: store, state: state)
                        .tag(row.node.id)
                }
            } header: {
                Text("Reading List", bundle: L10n.bundle)
            } footer: {
                Text("Unread items are listed first. Removing an item from the Reading List leaves it in the library.", bundle: L10n.bundle)
            }
        }
        OutlineGroup(library, children: \.children) { node in
            NodeRow(pathWidth: pathWidth, node: node, store: store, state: state)
        }
        if !trashed.isEmpty {
            Section {
                OutlineGroup(trashed, children: \.children) { node in
                    NodeRow(pathWidth: pathWidth, node: node, store: store, state: state)
                }
            } header: {
                Text("Recently Deleted")
            } footer: {
                Text("Deleted items stay here for 30 days, then they are removed for good. Restore puts an item back in its folder.")
            }
        }
    }

    /// True while the Delete Immediately confirmation is asked.
    private var purgeIsPresented: Binding<Bool> {
        Binding(
            get: { state.pendingPurge != nil },
            set: { if !$0 { state.pendingPurge = nil } }
        )
    }

    /// Whether `id` is in Recently Deleted, as a deleted item or one inside it.
    private func isDeleted(_ id: UUID) -> Bool {
        store.deleted.contains { $0.contains(id) }
    }

    private func list(pathWidth: CGFloat) -> some View {
        // The search runs once per change to the query or the library, not on every redraw.
        let found = state.searches.result(for: state.query, revision: store.revision, in: store.nodes)
        let trashed = store.deleted.matching(state.query)
        let reading = ReadingList.ordered(found.tree.leaves)
        let shown = found.count
        // Rows the search hid must not stay selected: Delete and Get Info act on the selection.
        let visible = Set(found.tree.allIDs + trashed.allIDs)
        return List(selection: $state.selection) {
            rows(displayed(found.tree), reading: reading, trashed: trashed, pathWidth: pathWidth)
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .navigationSubtitle("\(shown) \(shown == 1 ? "item" : "items")")
        .searchable(text: $state.query, placement: .toolbar, prompt: "Name, URL, command, or keyword")
        .focusedSceneValue(\.manageState, state)
        .onAppear { store.undoManager = undoManager }
        .overlay {
            if store.nodes.isEmpty && trashed.isEmpty {
                ContentUnavailableView {
                    Label("Your Library Is Empty", systemImage: "books.vertical")
                } description: {
                    Text("Add a link, app, or command.")
                } actions: {
                    Button("Add Bookmark") { state.present(.bookmark) }
                }
            } else if found.tree.isEmpty && trashed.isEmpty {
                ContentUnavailableView.search(text: state.query)
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            contextMenu(for: ids)
        } primaryAction: { ids in
            if ids.count == 1, let node = store.nodes.node(withID: ids.first!) {
                open(node)
            }
        }
        .onChange(of: state.query) { _, _ in state.selection.formIntersection(visible) }
        .onDeleteCommand { delete(state.selection.intersection(visible)) }
        .onKeyPress(.delete) {
            // Delete alone is handled by onDeleteCommand. Command-Delete matches Finder's Move to Trash.
            guard NSEvent.modifierFlags.contains(.command), !state.selection.isEmpty else { return .ignored }
            delete(state.selection)
            return .handled
        }
        .onKeyPress(.return) {
            guard state.selection.count == 1, let id = state.selection.first, store.nodes.node(withID: id) != nil else {
                return .ignored
            }
            state.renamingID = id
            return .handled
        }
        .confirmationDialog("Delete Immediately?", isPresented: purgeIsPresented, titleVisibility: .visible) {
            Button("Delete Immediately", role: .destructive) {
                if let ids = state.pendingPurge { store.deleteImmediately(ids) }
                state.pendingPurge = nil
            }
            Button("Cancel", role: .cancel) { state.pendingPurge = nil }
        } message: {
            Text("The items are removed from Recently Deleted. Undo right after this brings them back.")
        }
        .dropDestination(for: RowDrag.self) { drags, _ in
            // Rows dropped on empty space, not on a row, go to the top level.
            let moved = Set(drags.flatMap(\.ids))
            store.apply(rowDrop(moving: moved, onto: nil, in: store.nodes, listSorted: false), moving: moved)
            return true
        }
        .dropDestination(for: URL.self) { urls, _ in
            addDropped(urls)
            return true
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit…", systemImage: "pencil") {
                    state.editSelection(in: store)
                }
                .disabled(state.selection.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Bookmark…") { state.present(.bookmark) }
                    Button("Application…") { state.present(.application) }
                    Button("Terminal Command…") { state.present(.terminal) }
                    Button("Folder…") { state.present(.folder) }
                    Button("Divider…") { state.present(.divider) }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .help("Add a bookmark, application, command, folder, or divider (⌘N, ⇧⌘N)")
                .accessibilityLabel("Add")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    state.sheet = .snippets
                } label: {
                    Label("Snippets", systemImage: "text.quote")
                }
                .help("Manage the snippets you copy from Quick Open")
                .accessibilityLabel("Snippets")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    state.editSelection(in: store)
                } label: {
                    Label("Get Info", systemImage: "info.circle")
                }
                .help("Get Info for the selected items (⌘I)")
                .accessibilityLabel("Get Info")
                .disabled(state.selection.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                if let url = singleShareURL {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .help("Share the selected item")
                    .accessibilityLabel("Share")
                } else {
                    Button {} label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .help("Share the selected item")
                    .accessibilityLabel("Share")
                    .disabled(true)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    delete(state.selection)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help("Delete the selected items (⌘⌫)")
                .accessibilityLabel("Delete")
                .disabled(state.selection.isEmpty)
            }
        }
        .sheet(item: $state.sheet) { sheet in
            switch sheet {
            case .application:
                AppPickerSheet(store: store, state: state) { commit(sheet) }
            case .edit:
                EditSheet(store: store, state: state) { commit(sheet) }
            case .bulkEdit:
                BulkEditSheet(store: store, state: state)
            case .duplicates:
                DuplicatesSheet(store: store, state: state)
            case .snippets:
                SnippetsSheet()
            default:
                AddSheet(store: store, state: state) { commit(sheet) }
            }
        }
        .alert("Duplicates Merged", isPresented: Binding(
            get: { state.mergeSummary != nil },
            set: { if !$0 { state.mergeSummary = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.mergeSummary ?? "")
        }
    }

    /// Adds apps dragged from Finder and links dragged from a browser. Dropping a row from this window
    /// on empty space moves it to the top level instead.
    private func addDropped(_ urls: [URL]) {
        var newLinks: [(id: UUID, url: URL)] = []
        store.perform("Add") { nodes in
            for url in urls {
                if let existing = nodes.leaves.first(where: { $0.shareURL == url }) {
                    let moved = nodes.removeNode(existing.id)
                    nodes.append(moved ?? existing, to: nil)
                } else if url.isFileURL, url.pathExtension == "app" {
                    nodes.append(LibraryItem(name: appName(at: url.path), appPath: url.path))
                } else if !url.isFileURL {
                    let node = LibraryItem(name: url.host ?? url.absoluteString, url: url.absoluteString)
                    nodes.append(node)
                    newLinks.append((node.id, url))
                }
            }
        }
        for link in newLinks { SmartTitle.nameFromPage(link.id, url: link.url) }
    }

    /// Applies the open sheet's form to the bookmarks.
    private func commit(_ sheet: ManageState.Sheet) {
        let name = state.name.trimmingCharacters(in: .whitespaces)
        let folder = state.folderID
        switch sheet {
        case .bookmark:
            let url = state.url.trimmingCharacters(in: .whitespaces)
            store.perform("Add Bookmark") { $0.append(LibraryItem(name: name, url: url), to: folder) }
        case .terminal:
            let command = state.command.trimmingCharacters(in: .whitespaces)
            store.perform("Add Terminal Command") { $0.append(LibraryItem(name: name, command: command), to: folder) }
        case .folder:
            let shows = state.showsOpenAll
            store.perform("Add Folder") {
                $0.append(LibraryItem(name: name, children: [], showsOpenAll: shows ? nil : false), to: folder)
            }
        case .divider:
            store.perform("Add Divider") { $0.append(LibraryItem(name: name, isDivider: true), to: folder) }
        case .application:
            if let app = state.apps.first(where: { $0.id == state.appSelection }) {
                let arguments = clean(state.arguments)
                store.perform("Add Application") {
                    $0.append(LibraryItem(name: app.name, appPath: app.path, arguments: arguments), to: folder)
                }
            }
        case .snippets:
            break
        case .edit(let id):
            var node = state.draft
            node.shortcuts = node.shortcuts?.filter { !$0.isEmpty }
            if node.shortcuts?.isEmpty == true { node.shortcuts = nil }
            node.name = node.name.trimmingCharacters(in: .whitespaces)
            node.url = node.url.map { $0.trimmingCharacters(in: .whitespaces) }
            node.arguments = clean(node.arguments)
            node.keywords = clean(node.keywords)
            node.note = LibraryItem.cleanNote(node.note)
            node.command = node.appPath == nil ? node.command.map { $0.trimmingCharacters(in: .whitespaces) } : clean(node.command)
            node.promptLabel = node.isTemplate ? clean(node.promptLabel) : nil
            // The draft is a copy from when the sheet opened. Undo, a sync, or a link check may have changed the item since,
            // so only the fields the user edited are written, and everything else keeps its current value (contents of a
            // folder included). A link check's status is kept unless the address itself was changed.
            let base = state.draftBase
            store.perform("Edit") { $0.update(id) { current in
                var merged = current.applying(node, from: base)
                merged.linkStatus = merged.url == current.url ? current.linkStatus : nil
                current = merged
            } }
        case .bulkEdit, .duplicates:
            // These sheets apply their own changes.
            break
        }
    }

    /// Groups follow Finder: open, then info, then move and share, then Delete alone at the bottom.
    /// Items in Recently Deleted get Restore and Delete Immediately only.
    @ViewBuilder
    private func contextMenu(for ids: Set<UUID>) -> some View {
        if !ids.isEmpty, ids.allSatisfy(isDeleted) {
            Button("Restore") { store.restore(ids) }
            Button("Delete Immediately", role: .destructive) { state.pendingPurge = ids }
        } else if let id = ids.first, ids.count == 1, let node = store.nodes.node(withID: id) {
            if node.isOpenable {
                Button("Open") { open(node) }
            }
            if let children = node.children, node.showsOpenAllItem {
                Button("Open All") { openAll(children) }
                    .disabled(openAllSelection(in: children).isEmpty)
            }
            if let path = node.appPath {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
            }
            Divider()
            Button("Edit…") { state.edit(id, in: store) }
            Button("Rename") { state.renamingID = id }
            Divider()
        }
        if ids.count > 1 {
            Button("Edit…") { state.editMany(ids) }
            Divider()
        }
        readingListMenu(for: ids)
        if !ids.isEmpty {
            Menu("Move to") {
                Button("Top level") { store.move(ids, to: nil) }
                ForEach(store.nodes.folders(skipping: ids)) { folder in
                    Button(folder.title) { store.move(ids, to: folder.id) }
                }
            }
            if ids.count == 1, let id = ids.first, let item = store.nodes.node(withID: id)?.shareURL {
                ShareLink("Share…", item: item)
            }
            Divider()
            Button("Delete", role: .destructive) { delete(ids) }
        }
    }

    /// Adds bookmarks to the Reading List, and marks or removes the ones already in it. Only the choices that apply
    /// to the selection are listed.
    @ViewBuilder
    private func readingListMenu(for ids: Set<UUID>) -> some View {
        let items = ids.compactMap { store.nodes.node(withID: $0) }
        let addable = Set(items.filter { $0.canReadLater && $0.readLater == nil }.map(\.id))
        let listed = Set(items.filter { $0.readLater != nil }.map(\.id))
        let unread = Set(items.filter { $0.readLater == .unread }.map(\.id))
        let read = Set(items.filter { $0.readLater == .read }.map(\.id))
        if !addable.isEmpty || !listed.isEmpty {
            if !addable.isEmpty {
                Button(ReadingList.Action.add.title) { store.changeReadingList(addable, .add) }
            }
            if !unread.isEmpty {
                Button(ReadingList.Action.markRead.title) { store.changeReadingList(unread, .markRead) }
            }
            if !read.isEmpty {
                Button(ReadingList.Action.markUnread.title) { store.changeReadingList(read, .markUnread) }
            }
            if !listed.isEmpty {
                Button(ReadingList.Action.remove.title) { store.changeReadingList(listed, .remove) }
            }
            Divider()
        }
    }

    /// Live items go to Recently Deleted. Items already there are removed for good, after the user confirms.
    private func delete(_ ids: Set<UUID>) {
        let live = ids.filter { store.nodes.node(withID: $0) != nil }
        if !live.isEmpty { store.delete(live) }
        let gone = ids.subtracting(live)
        if !gone.isEmpty { state.pendingPurge = gone }
        state.selection.subtract(ids)
    }
}

/// A row of the Reading List section. The item is also a library row, so the section's row needs its own id.
private struct ReadingRow: Identifiable {
    let node: LibraryItem
    var id: String { "reading-\(node.id.uuidString)" }
}

/// Trims `text` and returns nil when nothing is left.
private func clean(_ text: String?) -> String? {
    let trimmed = (text ?? "").trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? nil : trimmed
}
