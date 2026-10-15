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
    /// An application also needs the same arguments, and a link the same browser. Otherwise a merge would remove an
    /// item that opens the same thing in another way, and the sheet does not show either setting.
    static func key(for item: LibraryItem) -> String? {
        if let path = item.appPath {
            let arguments = (item.arguments ?? "").trimmingCharacters(in: .whitespaces)
            return "app:" + URL(fileURLWithPath: path).standardized.path + "|" + arguments
        }
        guard let url = item.url, !url.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return "link:" + normalizedLink(url) + "|" + (item.browser ?? "")
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

    /// What a merge did: the new tree, and the counts and names the summary alert shows.
    struct MergeResult {
        let nodes: [LibraryItem]
        /// Items in the merged groups, kept and removed.
        let mergedCount: Int
        /// Shortcuts moved from removed copies to the item kept.
        let inheritedCount: Int
        /// Shortcuts of removed copies that were not moved, as "⌘D (Docs copy)", because the key was already used.
        let conflicts: [String]
        /// The removed copies as they were, with their notes, colors, icons and Reading List state. The caller moves
        /// them to Recently Deleted, with `deletedFrom` set to the folder each was in, so nothing is lost.
        let removed: [LibraryItem]

        /// The alert text, such as "Merged 3 items. 1 shortcut was kept from another copy."
        var summary: String {
            var sentences = ["Merged \(mergedCount) items."]
            if inheritedCount > 0 {
                sentences.append(inheritedCount == 1 ? "1 shortcut was kept from another copy."
                    : "\(inheritedCount) shortcuts were kept from other copies.")
            }
            if !conflicts.isEmpty {
                sentences.append("Not kept, because the key is already used: " + conflicts.joined(separator: ", ") + ".")
            }
            return sentences.joined(separator: " ")
        }
    }

    /// Keeps one item per group and removes the others, returning the new tree. `choices` maps a group id to the item
    /// to keep. A group without a choice keeps its first item. The kept item keeps its own folder and shortcuts, and
    /// its keywords become the unique words of every item in the group. It also takes each shortcut of the removed
    /// copies whose key combination no remaining item uses. Those that clash are dropped and listed in the result.
    static func merge(_ nodes: [LibraryItem], keeping choices: [String: UUID] = [:]) -> MergeResult {
        let found = groups(in: nodes)
        var kept: [(group: Group, item: LibraryItem, others: [LibraryItem])] = []
        for group in found {
            let item = group.items.first { $0.id == choices[group.id] } ?? group.items[0]
            kept.append((group, item, group.items.filter { $0.id != item.id }))
        }
        let removedIDs = Set(kept.flatMap { $0.others.map(\.id) })
        var taken = Set(everyNode(nodes).filter { !removedIDs.contains($0.id) }.flatMap { ($0.shortcuts ?? []).filter { !$0.isEmpty }.map(comboKey) })

        var result = nodes
        var inherited = 0
        var conflicts: [String] = []
        var removed: [LibraryItem] = []
        for entry in kept {
            var moved: [Shortcut] = []
            for other in entry.others {
                for shortcut in (other.shortcuts ?? []) where !shortcut.isEmpty {
                    if taken.insert(comboKey(shortcut)).inserted {
                        moved.append(shortcut)
                    } else {
                        conflicts.append("\(shortcut.description) (\(other.name))")
                    }
                }
            }
            let keywords = joinKeywords([entry.item.keywords] + entry.others.map(\.keywords))
            result.update(entry.item.id) {
                $0.keywords = keywords
                if !moved.isEmpty { $0.shortcuts = ($0.shortcuts ?? []) + moved }
            }
            inherited += moved.count
            for other in entry.others {
                var copy = other
                copy.deletedFrom = LibrarySync.parentID(of: other.id, in: nodes)
                removed.append(copy)
                result.removeNode(other.id)
            }
        }
        return MergeResult(nodes: result, mergedCount: found.reduce(0) { $0 + $1.items.count },
                           inheritedCount: inherited, conflicts: conflicts, removed: removed)
    }

    /// Every node in the tree, folders included.
    private static func everyNode(_ nodes: [LibraryItem]) -> [LibraryItem] {
        nodes.flatMap { [$0] + everyNode($0.children ?? []) }
    }

    /// The key combination of a shortcut, so two shortcuts that do the same thing compare equal. Openers that
    /// differ only in "open in new window" still clash.
    static func comboKey(_ shortcut: Shortcut) -> String {
        "\(shortcut.keyCode)|\(shortcut.key.lowercased())|\(shortcut.modifiers)|\(shortcut.button ?? -1)|\(shortcut.gesture ?? "")"
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
