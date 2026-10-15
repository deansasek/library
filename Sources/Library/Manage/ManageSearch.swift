import Foundation

/// What the search field's scope bar limits the results to. The scope narrows the same results the query does, so
/// a folder shows only when it has something in the scope, or when it is itself in the scope.
enum SearchScope: String, CaseIterable, Hashable {
    case all, bookmarks, apps, commands, folders

    var title: String {
        switch self {
        case .all: return "All"
        case .bookmarks: return "Bookmarks"
        case .apps: return "Apps"
        case .commands: return "Commands"
        case .folders: return "Folders"
        }
    }

    /// Whether a leaf (a bookmark, app, command, or divider) is in this scope. Dividers are only in All.
    func accepts(_ item: LibraryItem) -> Bool {
        switch self {
        case .all: return true
        case .bookmarks: return item.url != nil
        case .apps: return item.appPath != nil
        case .commands: return item.command != nil && item.appPath == nil
        case .folders: return false
        }
    }

    /// Whether folders are results in this scope.
    var acceptsFolders: Bool { self == .all || self == .folders }
}

extension Array where Element == LibraryItem {
    /// The tree narrowed to what matches `query` and is in `scope`, for the search field in the Library window.
    /// Every word must match the name, URL, command, or keywords of an item. A folder whose name matches keeps the
    /// contents in the scope, and any other folder keeps only the matching items in it. Dividers never match, so they
    /// are left out of results. An empty query in the All scope returns the tree as it is.
    func matching(_ query: String, scope: SearchScope = .all) -> [LibraryItem] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty || scope != .all else { return self }
        return filter(words: words, scope: scope)
    }

    /// The names of up to `limit` distinct bookmarks and apps that match `query`, for the search suggestions.
    /// Nothing is suggested for an empty query.
    func searchSuggestions(for query: String, limit: Int = 5) -> [String] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        var seen = Set<String>()
        var names: [String] = []
        for item in matching(query).leaves where seen.insert(item.name).inserted {
            names.append(item.name)
            if names.count == limit { break }
        }
        return names
    }

    /// The number of folders in the tree, including folders inside folders.
    var folderCount: Int {
        reduce(0) { total, node in
            guard let children = node.children else { return total }
            return total + 1 + children.folderCount
        }
    }

    private func filter(words: [String], scope: SearchScope) -> [LibraryItem] {
        compactMap { node -> LibraryItem? in
            guard let children = node.children else {
                guard node.isDivider != true, scope.accepts(node),
                      Self.matches([node.name, node.url, node.command, node.keywords], words: words) else { return nil }
                return node
            }
            if Self.matches([node.name], words: words) {
                var folder = node
                folder.children = children.scoped(scope)
                guard scope.acceptsFolders || folder.children?.isEmpty == false else { return nil }
                return folder
            }
            let kept = children.filter(words: words, scope: scope)
            guard !kept.isEmpty else { return nil }
            var folder = node
            folder.children = kept
            return folder
        }
    }

    /// The contents of a folder whose name matched, narrowed to the scope only. Dividers stay in All.
    private func scoped(_ scope: SearchScope) -> [LibraryItem] {
        compactMap { node -> LibraryItem? in
            guard let children = node.children else {
                return scope.accepts(node) ? node : nil
            }
            var folder = node
            folder.children = children.scoped(scope)
            guard scope.acceptsFolders || folder.children?.isEmpty == false else { return nil }
            return folder
        }
    }

    private static func matches(_ fields: [String?], words: [String]) -> Bool {
        words.allSatisfy { word in
            fields.contains { $0?.localizedCaseInsensitiveContains(word) == true }
        }
    }
}

/// The rows the Library window lists: the library tree in the window's order, the Reading List, Recently Deleted,
/// and the rows the search leaves visible. Searching and sorting a large library takes a noticeable time, and the
/// window redraws on every selection, so these are built once per change (see ManageListingCache).
struct ManageListing {
    /// The library rows the search leaves in view, in the order the window shows them.
    let tree: [LibraryItem]
    /// The bookmarks and apps in the search result, or the folders when the scope is Folders, for the window subtitle.
    let count: Int
    /// The Reading List rows, unread first.
    let reading: [LibraryItem]
    /// The Recently Deleted rows the search leaves in view.
    let trashed: [LibraryItem]
    /// The ids of the rows listed, so a selection can drop the rows the search hid.
    let visible: Set<UUID>

    static func build(query: String, scope: SearchScope, nodes: [LibraryItem], deleted: [LibraryItem],
                      sort: ManageState.SortKey?, ascending: Bool, counts: [String: Int], opened: [String: Date]) -> ManageListing {
        let found = nodes.matching(query, scope: scope)
        let trashed = deleted.matching(query, scope: scope)
        return ManageListing(
            tree: arranged(found, by: sort, ascending: ascending, counts: counts, opened: opened),
            count: scope == .folders ? found.folderCount : found.leaves.count,
            reading: ReadingList.ordered(found.leaves),
            trashed: trashed,
            visible: Set(found.allIDs + trashed.allIDs)
        )
    }

    /// The nodes in the order the window shows them: yours, or sorted by a column at every level, folders first.
    static func arranged(_ nodes: [LibraryItem], by sort: ManageState.SortKey?, ascending: Bool,
                         counts: [String: Int], opened: [String: Date]) -> [LibraryItem] {
        guard let key = sort else { return nodes }
        func value(_ node: LibraryItem) -> String {
            switch key {
            case .name, .mostUsed, .recentlyOpened: return node.name
            case .shortcut: return node.shortcuts?.first?.description ?? "\u{10FFFF}"
            case .path: return node.url ?? node.command ?? node.appPath ?? ""
            }
        }
        var result = nodes.map { node -> LibraryItem in
            var node = node
            node.children = node.children.map { arranged($0, by: sort, ascending: ascending, counts: counts, opened: opened) }
            return node
        }
        if key == .mostUsed || key == .recentlyOpened {
            // Within each section between dividers, folders keep their places first, as they do in the other orders, and
            // the items are ordered by their use. A divider stays where it is, so no item moves across it.
            return UsageOrder.withinSections(result) { section in
                let folders = section.filter(\.isFolder)
                let items = section.filter { !$0.isFolder }
                let ordered = key == .mostUsed
                    ? UsageOrder.mostUsed(items, counts: counts)
                    : UsageOrder.recentlyOpened(items, opened: opened)
                return folders + ordered
            }
        }
        result.sort { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            let order = value(a).localizedCaseInsensitiveCompare(value(b))
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
        return result
    }
}

/// The last rows the Library window built. They are kept between redraws and rebuilt only when the query, the scope,
/// the library revision, the usage counts, or the sort changes.
final class ManageListingCache {
    struct Key: Equatable {
        let query: String
        let scope: SearchScope
        /// Changes whenever the library changes (`LibraryStore.revision`).
        let revision: Int
        /// Changes whenever an item is opened, since Most Used and Recently Opened depend on it (`LibraryStore.usageRevision`).
        let usage: Int
        let sort: ManageState.SortKey?
        let ascending: Bool
    }

    private var last: (key: Key, listing: ManageListing)?

    func listing(for key: Key, build: () -> ManageListing) -> ManageListing {
        if let last, last.key == key { return last.listing }
        let listing = build()
        last = (key, listing)
        return listing
    }
}
