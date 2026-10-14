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
        case bookmark, terminal, folder, divider, application, edit(UUID)
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
        let isSymbol = node.icon.map { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil } ?? true
        iconTab = isSymbol ? .symbols : .emoji
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
        recordingIndex = nil
        showIconPicker = false
        iconSearch = ""
        self.sheet = sheet
    }
}
