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
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
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

    /// The nodes in the order the window shows them: yours, or sorted by a column at every level, folders first.
    private func displayed(_ nodes: [LibraryItem]) -> [LibraryItem] {
        guard let key = state.sortKey else { return nodes }
        func value(_ node: LibraryItem) -> String {
            switch key {
            case .name: return node.name
            case .shortcut: return node.shortcuts?.first?.description ?? "\u{10FFFF}"
            case .path: return node.url ?? node.command ?? node.appPath ?? ""
            }
        }
        var result = nodes.map { node -> LibraryItem in
            var node = node
            node.children = node.children.map(displayed)
            return node
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
            }
        }
        .frame(minWidth: 680, idealWidth: 780, minHeight: 300, idealHeight: 420)
    }

    private func list(pathWidth: CGFloat) -> some View {
        List(displayed(store.nodes), children: \.children, selection: $state.selection) { node in
            NodeRow(pathWidth: pathWidth, node: node, store: store, state: state)
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .navigationSubtitle("\(store.nodes.leaves.count) \(store.nodes.leaves.count == 1 ? "item" : "items")")
        .focusedSceneValue(\.manageState, state)
        .onAppear { store.undoManager = undoManager }
        .overlay {
            if store.nodes.isEmpty {
                ContentUnavailableView {
                    Label("Your Library Is Empty", systemImage: "books.vertical")
                } description: {
                    Text("Add a link, app, or command.")
                } actions: {
                    Button("Add Bookmark") { state.present(.bookmark) }
                }
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            contextMenu(for: ids)
        } primaryAction: { ids in
            if ids.count == 1, let node = store.nodes.node(withID: ids.first!) {
                open(node)
            }
        }
        .onDeleteCommand { delete(state.selection) }
        .onKeyPress(.delete) {
            // Delete alone is handled by onDeleteCommand. Command-Delete matches Finder's Move to Trash.
            guard NSEvent.modifierFlags.contains(.command), !state.selection.isEmpty else { return .ignored }
            delete(state.selection)
            return .handled
        }
        .onKeyPress(.return) {
            guard state.selection.count == 1 else { return .ignored }
            state.renamingID = state.selection.first
            return .handled
        }
        .dropDestination(for: String.self) { items, _ in
            store.move(Set(items.flatMap(ids(in:))), to: nil)
            return true
        }
        .dropDestination(for: URL.self) { urls, _ in
            addDropped(urls)
            return true
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Get Info", systemImage: "info.circle") {
                    if let id = state.selection.first { state.edit(id, in: store) }
                }
                .disabled(state.selection.count != 1)
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
            }
        }
        .sheet(item: $state.sheet) { sheet in
            switch sheet {
            case .application:
                AppPickerSheet(store: store, state: state) { commit(sheet) }
            case .edit:
                EditSheet(store: store, state: state) { commit(sheet) }
            default:
                AddSheet(store: store, state: state) { commit(sheet) }
            }
        }
    }

    /// Adds apps dragged from Finder and links dragged from a browser. Dropping a row from this window
    /// on empty space moves it to the top level instead.
    private func addDropped(_ urls: [URL]) {
        store.perform("Add") { nodes in
            for url in urls {
                if let existing = nodes.leaves.first(where: { $0.shareURL == url }) {
                    let moved = nodes.removeNode(existing.id)
                    nodes.append(moved ?? existing, to: nil)
                } else if url.isFileURL, url.pathExtension == "app" {
                    nodes.append(LibraryItem(name: appName(at: url.path), appPath: url.path))
                } else if !url.isFileURL {
                    nodes.append(LibraryItem(name: url.host ?? url.absoluteString, url: url.absoluteString))
                }
            }
        }
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
            store.perform("Add Folder") { $0.append(LibraryItem(name: name, children: []), to: folder) }
        case .divider:
            store.perform("Add Divider") { $0.append(LibraryItem(name: name, isDivider: true), to: folder) }
        case .application:
            if let app = state.apps.first(where: { $0.id == state.appSelection }) {
                let arguments = clean(state.arguments)
                store.perform("Add Application") {
                    $0.append(LibraryItem(name: app.name, appPath: app.path, arguments: arguments), to: folder)
                }
            }
        case .edit(let id):
            var node = state.draft
            node.shortcuts = node.shortcuts?.filter { !$0.isEmpty }
            if node.shortcuts?.isEmpty == true { node.shortcuts = nil }
            node.name = node.name.trimmingCharacters(in: .whitespaces)
            node.url = node.url.map { $0.trimmingCharacters(in: .whitespaces) }
            node.arguments = clean(node.arguments)
            node.keywords = clean(node.keywords)
            node.command = node.appPath == nil ? node.command.map { $0.trimmingCharacters(in: .whitespaces) } : clean(node.command)
            node.promptLabel = node.isTemplate ? clean(node.promptLabel) : nil
            store.perform("Edit") { $0.update(id) { $0 = node } }
        }
    }

    /// Groups follow Finder: open, then info, then move and share, then Delete alone at the bottom.
    @ViewBuilder
    private func contextMenu(for ids: Set<UUID>) -> some View {
        if let id = ids.first, ids.count == 1, let node = store.nodes.node(withID: id) {
            if node.isOpenable {
                Button("Open") { open(node) }
            }
            if let path = node.appPath {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
            }
            Divider()
            Button("Get Info") { state.edit(id, in: store) }
            Button("Rename") { state.renamingID = id }
            Divider()
        }
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

    private func delete(_ ids: Set<UUID>) {
        store.perform("Delete") { nodes in ids.forEach { nodes.removeNode($0) } }
        state.selection.subtract(ids)
    }
}

/// Trims `text` and returns nil when nothing is left.
private func clean(_ text: String?) -> String? {
    let trimmed = (text ?? "").trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? nil : trimmed
}

/// Parses the comma-separated ids a drag carries.
func ids(in payload: String) -> [UUID] {
    payload.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
}
