import SwiftUI

/// Get Info for an item chosen in a menu. The Library window may not be open yet, so the request waits here until
/// the window takes it when it appears, or is told by the notification when it is already open.
@MainActor
enum EditRequest {
    static let notification = Notification.Name("LibraryEditRequested")
    private static var pending: UUID?

    static func post(_ id: UUID) {
        pending = id
        NotificationCenter.default.post(name: notification, object: nil)
    }

    /// The waiting request, if any. It is taken once.
    static func take() -> UUID? {
        let id = pending
        pending = nil
        return id
    }
}

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

    /// What the list is sorted by. Sorting only changes what the window shows, not your menu order. The first three
    /// are columns. Most used and recently opened come from the sort menu, and always put the largest value first.
    /// String-backed so the window can store it with `@SceneStorage`. The raw values are part of saved state, so keep them.
    enum SortKey: String { case name, shortcut, path, mostUsed, recentlyOpened }

    @Published var sortKey: SortKey?
    @Published var ascending = true
    @Published var selection: Set<UUID> = []
    @Published var renamingID: UUID?
    /// The row a drag is over, for the drop highlight.
    @Published var dropTarget: UUID?
    /// True while a link or app is dragged over the list, for the list's drop outline.
    @Published var isListDropTargeted = false
    @Published var sheet: Sheet?
    /// Items the user chose to delete for good. Set only after the confirmation is asked.
    @Published var pendingPurge: Set<UUID>?
    /// The text in the window's search field. Separate from `search`, which filters the app picker.
    @Published var query = ""
    /// Counts each Find (⌘F) request, so the window moves focus to its search field.
    @Published var searchFocusRequest = 0
    /// The search field's scope bar. It narrows the results of `query`.
    @Published var scope = SearchScope.all
    /// The rows for the current query, scope, and sort, kept between redraws.
    let listings = ManageListingCache()

    // Add sheets.
    @Published var name = ""
    @Published var url = ""
    @Published var command = ""
    @Published var arguments = ""
    @Published var folderID: UUID?
    @Published var apps: [InstalledApp] = []
    @Published var search = ""
    @Published var appSelection: InstalledApp.ID?
    /// The New Folder sheet's Show Open All toggle.
    @Published var showsOpenAll = true

    // Edit sheet.
    @Published var draft = LibraryItem(name: "")
    /// The item as it was when the edit sheet opened. Save applies only the fields that differ from it.
    var draftBase = LibraryItem(name: "")
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
        draftBase = node
        fieldsText = (node.templateFields ?? []).joined(separator: ", ")
        let isSymbol = node.icon.map { symbolImage($0) != nil } ?? true
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

    /// The sort menu's choice. Nil goes back to your own order. A choice starts ascending, as a column does.
    func chooseSort(_ key: SortKey?) {
        sortKey = key
        ascending = true
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

    func focusSearch() {
        searchFocusRequest += 1
    }

    func present(_ sheet: Sheet) {
        name = ""
        url = ""
        command = ""
        arguments = ""
        search = ""
        appSelection = nil
        showsOpenAll = true
        keepChoices = [:]
        // The folder from an earlier sheet may have been deleted or moved since, so each sheet starts at the top level.
        folderID = nil
        recordingIndex = nil
        showIconPicker = false
        iconSearch = ""
        fieldsText = ""
        self.sheet = sheet
    }
}
