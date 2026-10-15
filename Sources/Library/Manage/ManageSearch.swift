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

/// The last search in the Library window. Searching a large library takes a noticeable time, and the window
/// redraws on every selection, so the result is kept until the query, the scope, or the library changes.
final class SearchCache {
    struct Result {
        /// The tree the search leaves in view.
        let tree: [LibraryItem]
        /// The bookmarks and apps in `tree`, or the folders when the scope is Folders, for the window subtitle.
        let count: Int
    }

    private var last: (query: String, scope: SearchScope, revision: Int, result: Result)?

    /// `revision` changes whenever `nodes` changes, so a stale result is never returned.
    func result(for query: String, scope: SearchScope = .all, revision: Int, in nodes: [LibraryItem]) -> Result {
        if let last, last.query == query, last.scope == scope, last.revision == revision {
            return last.result
        }
        let tree = nodes.matching(query, scope: scope)
        let count = scope == .folders ? tree.folderCount : tree.leaves.count
        let result = Result(tree: tree, count: count)
        last = (query, scope, revision, result)
        return result
    }
}
