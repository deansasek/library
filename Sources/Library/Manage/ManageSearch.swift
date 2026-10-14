import Foundation

extension Array where Element == LibraryItem {
    /// The tree narrowed to what matches `query`, for the search field in the Library window.
    /// Every word must match the name, URL, command, or keywords of an item. A folder whose name
    /// matches keeps all of its contents, and any other folder keeps only the matching items in it.
    /// Dividers never match, so they are left out of results. An empty query returns the tree as it is.
    func matching(_ query: String) -> [LibraryItem] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return self }
        return filter(words: words)
    }

    private func filter(words: [String]) -> [LibraryItem] {
        compactMap { node -> LibraryItem? in
            guard let children = node.children else {
                guard node.isDivider != true,
                      Self.matches([node.name, node.url, node.command, node.keywords], words: words) else { return nil }
                return node
            }
            if Self.matches([node.name], words: words) {
                return node
            }
            let kept = children.filter(words: words)
            guard !kept.isEmpty else { return nil }
            var folder = node
            folder.children = kept
            return folder
        }
    }

    private static func matches(_ fields: [String?], words: [String]) -> Bool {
        words.allSatisfy { word in
            fields.contains { $0?.localizedCaseInsensitiveContains(word) == true }
        }
    }
}
