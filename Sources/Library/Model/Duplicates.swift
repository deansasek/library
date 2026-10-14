import Foundation

/// Finds bookmarks and applications that open the same link or application, and merges each group into one item.
enum Duplicates {
    /// Items that open the same link or application. `items` are in display order, so the first one is kept by default.
    struct Group: Identifiable {
        let id: String
        let items: [LibraryItem]

        var isApp: Bool { id.hasPrefix("app:") }
    }

    /// The text that makes two items duplicates, or nil for items that open nothing.
    static func key(for item: LibraryItem) -> String? {
        if let path = item.appPath {
            return "app:" + URL(fileURLWithPath: path).standardized.path
        }
        guard let url = item.url, !url.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return "link:" + normalizedLink(url)
    }

    /// Lowercases the scheme and host and removes a trailing slash. A missing scheme counts as https, as it does when
    /// the link opens. The path and query keep their case, because servers may treat them as case sensitive.
    static func normalizedLink(_ text: String) -> String {
        var link = text.trimmingCharacters(in: .whitespaces)
        if !link.contains("://") { link = "https://" + link }
        guard let separator = link.range(of: "://") else { return link }
        let scheme = link[..<separator.lowerBound].lowercased()
        let rest = link[separator.upperBound...]
        let end = rest.firstIndex { "/?#".contains($0) } ?? rest.endIndex
        let host = rest[..<end].lowercased()
        var path = String(rest[end...])
        if path.hasSuffix("/") { path.removeLast() }
        return scheme + "://" + host + path
    }

    /// Every group of two or more leaves with the same key, in the order the library shows them.
    static func groups(in nodes: [LibraryItem]) -> [Group] {
        var order: [String] = []
        var buckets: [String: [LibraryItem]] = [:]
        for item in nodes.leaves {
            guard let key = key(for: item) else { continue }
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(item)
        }
        return order.compactMap { key in
            guard let items = buckets[key], items.count > 1 else { return nil }
            return Group(id: key, items: items)
        }
    }

    /// The folder path of item `id` with " / " between folders, or "Top level". Nil when the item is not in `nodes`.
    static func folderTitle(of id: UUID, in nodes: [LibraryItem], under path: String = "") -> String? {
        for node in nodes {
            if node.id == id { return path.isEmpty ? "Top level" : path }
            if let children = node.children {
                let title = path.isEmpty ? node.name : path + " / " + node.name
                if let found = folderTitle(of: id, in: children, under: title) { return found }
            }
        }
        return nil
    }

    /// Keeps one item per group and removes the others, returning the new tree. `choices` maps a group id to the item
    /// to keep. A group without a choice keeps its first item. The kept item keeps its own shortcuts and folder, and its
    /// keywords become the unique words of every item in the group.
    static func merged(_ nodes: [LibraryItem], keeping choices: [String: UUID] = [:]) -> [LibraryItem] {
        var result = nodes
        for group in groups(in: nodes) {
            let kept = group.items.first { $0.id == choices[group.id] } ?? group.items[0]
            let others = group.items.filter { $0.id != kept.id }
            let keywords = joinKeywords([kept.keywords] + others.map(\.keywords))
            result.update(kept.id) { $0.keywords = keywords }
            for other in others {
                result.removeNode(other.id)
            }
        }
        return result
    }

    /// The words of every text, in order, without repeats. Case is ignored when comparing, and the first spelling wins.
    static func joinKeywords(_ texts: [String?]) -> String? {
        var seen = Set<String>()
        var words: [String] = []
        for text in texts {
            for word in (text ?? "").split(whereSeparator: \.isWhitespace) {
                let word = String(word)
                if seen.insert(word.lowercased()).inserted {
                    words.append(word)
                }
            }
        }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }
}
