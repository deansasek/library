import SwiftUI

enum IconTab: String, CaseIterable {
    case symbols = "Symbols"
    case emoji = "Emoji"
}

/// State for the sheets and inline rename. Objects instead of `@State` because
/// the `@State` macro plugin needs a full Xcode install.
@MainActor
final class ManageState: ObservableObject {
    enum Sheet: Identifiable, Hashable {
        case bookmark, terminal, folder, divider, application, edit(UUID), bulkEdit, duplicates, snippets
        var id: Self { self }
    }

    /// A column the list is sorted by. Sorting only changes what the window shows, not your menu order.
    enum SortKey { case name, shortcut, path }

    @Published var sortKey: SortKey?
    @Published var ascending = true
    @Published var selection: Set<UUID> = []
    @Published var renamingID: UUID?
    /// The row a drag is over, for the drop highlight.
    @Published var dropTarget: UUID?
    @Published var sheet: Sheet?
    /// The text in the window's search field. Separate from `search`, which filters the app picker.
    @Published var query = ""
    /// The search result for `query`, kept between redraws.
    let searches = SearchCache()

    // Add sheets.
    @Published var name = ""
    @Published var url = ""
    @Published var command = ""
    @Published var arguments = ""
    @Published var folderID: UUID?
    @Published var apps: [InstalledApp] = []
    @Published var search = ""
    @Published var appSelection: InstalledApp.ID?

    // Edit sheet.
    @Published var draft = LibraryItem(name: "")
    @Published var recordingIndex: Int?
    @Published var showIconPicker = false
    @Published var iconSearch = ""
    @Published var iconTab = IconTab.symbols
    /// The Fields text as typed, such as "query:Search, sort". The draft's `templateFields` is parsed from it.
    @Published var fieldsText = ""

    // Bulk edit sheet: the items it applies to, and the changes so far.
    @Published var bulkIDs: Set<UUID> = []
    @Published var bulkEdit = BulkEdit()

    // Find Duplicates sheet: the item to keep in each group, by group id. Missing groups keep their first item.
    @Published var keepChoices: [String: UUID] = [:]
    /// The summary of the last merge, shown in an alert until dismissed.
    @Published var mergeSummary: String?

    var filteredApps: [InstalledApp] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var isValid: Bool {
        func filled(_ text: String?) -> Bool { !(text ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        switch sheet {
        case .bookmark: return filled(name) && filled(url)
        case .terminal: return filled(name) && filled(command)
        case .folder, .divider: return filled(name)
        case .application: return appSelection != nil
        case .bulkEdit: return !bulkEdit.changesNothing
        case .duplicates: return true
        case .snippets: return false
        case .edit:
            guard filled(draft.name) else { return false }
            if draft.url != nil { return filled(draft.url) }
            if draft.appPath == nil, draft.command != nil { return filled(draft.command) }
            return true
        case nil: return false
        }
    }

    /// Opens the edit sheet for item `id`, on the icon tab that matches its current icon.
    func edit(_ id: UUID, in store: LibraryStore) {
        guard let node = store.nodes.node(withID: id) else { return }
        present(.edit(id))
        draft = node
        fieldsText = (node.templateFields ?? []).joined(separator: ", ")
        let isSymbol = node.icon.map { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil } ?? true
        iconTab = isSymbol ? .symbols : .emoji
    }

    /// Get Info for the selection: the single-item sheet for one item, the bulk sheet for several.
    func editSelection(in store: LibraryStore) {
        if selection.count == 1, let id = selection.first {
            edit(id, in: store)
        } else if selection.count > 1 {
            editMany(selection)
        }
    }

    /// Opens the bulk sheet for the items in `ids`, with no changes yet.
    func editMany(_ ids: Set<UUID>) {
        present(.bulkEdit)
        bulkIDs = ids
        bulkEdit = BulkEdit()
    }

    /// Clicking a column header sorts by it, then reverses, then goes back to your own order.
    func toggleSort(_ key: SortKey) {
        if sortKey != key {
            sortKey = key
            ascending = true
        } else if ascending {
            ascending = false
        } else {
            sortKey = nil
            ascending = true
        }
    }

    func present(_ sheet: Sheet) {
        name = ""
        url = ""
        command = ""
        arguments = ""
        search = ""
        appSelection = nil
        keepChoices = [:]
        recordingIndex = nil
        showIconPicker = false
        iconSearch = ""
        fieldsText = ""
        self.sheet = sheet
    }
}
