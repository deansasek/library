import SwiftUI

/// One row in Quick Open: a library item, or an action on what was typed.
struct QuickOpenResult: Identifiable {
    enum Kind {
        case item(LibraryItem, folder: String)
        case openLink(URL)
        case addLink(URL)
        case webSearch(String)
        case clip(ClipItem)
        /// The link or application on the clipboard, offered as an addition to the library.
        case addSuggestion(AddSuggestion)
        /// An arithmetic or unit answer. Return copies the value.
        case answer(value: String, detail: String)
    }

    let kind: Kind
    let id: String
    /// With an empty search, the divider title this item starts, so the list matches the menu.
    var section: String?

    var clip: ClipItem? {
        if case .clip(let item) = kind { return item }
        return nil
    }

    var node: LibraryItem? {
        if case .item(let node, _) = kind { return node }
        return nil
    }

    /// Library items and clipboard items have actions on Tab and right-click.
    var hasActions: Bool {
        switch kind {
        case .item, .clip: return true
        default: return false
        }
    }

    var title: String {
        switch kind {
        case .answer(let value, _): return value
        case .addSuggestion(let suggestion): return suggestion.title
        case .clip(let item): return item.title
        case .item(let node, _): return node.name
        case .openLink(let url): return "Open \(url.host ?? url.absoluteString)"
        case .addLink(let url): return "Add “\(url.host ?? url.absoluteString)” to Library"
        case .webSearch(let query): return "Search the Web for “\(query)”"
        }
    }

    /// What the item opens, with its folder in front.
    @MainActor var subtitle: String {
        switch kind {
        case .answer(_, let detail): return "\(detail) · Return copies the answer"
        case .addSuggestion(let suggestion): return suggestion.subtitle
        case .clip(let item): return item.subtitle
        case .item(let node, let folder):
            let detail = node.url ?? node.command ?? node.appPath ?? ""
            return folder.isEmpty ? detail : "\(folder) · \(detail)"
        case .openLink(let url), .addLink(let url): return url.absoluteString
        case .webSearch: return "Google"
        }
    }

    /// Items that match every word of `query` in the name, keywords, target, or folder. Best matches first,
    /// then the most opened. An empty query lists the most opened first, then the tree order.
    static func search(_ query: String, in nodes: [LibraryItem], counts: [String: Int]) -> [QuickOpenResult] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        if words.isEmpty {
            // The library as the menu shows it: items under their dividers.
            return nodes.sections.flatMap { section -> [QuickOpenResult] in
                var items = flatten(section.nodes, folder: "")
                if !items.isEmpty { items[0].section = section.title ?? "Library" }
                return items
            }
        }
        let all = flatten(nodes, folder: "")
        let scored: [(result: QuickOpenResult, score: Int, index: Int)] = all.enumerated().compactMap { index, result in
            guard !words.isEmpty, let node = result.node, case .item(_, let folder) = result.kind else {
                return (result, 0, index)
            }
            let name = node.name.lowercased()
            let keywords = "\(node.keywords ?? "") \(node.color ?? "")".lowercased().split(separator: " ").map(String.init)
            let other = "\(node.url ?? "") \(node.command ?? "") \(node.appPath ?? "") \(folder) \(keywords.joined(separator: " "))".lowercased()
            var total = 0
            for word in words {
                let score = name.hasPrefix(word) || keywords.contains(where: { $0.hasPrefix(word) }) ? 4
                    : name.contains(word) ? 3 : isSubsequence(word, of: name) ? 1 : other.contains(word) ? 2 : 0
                if score == 0 { return nil }
                total += score
            }
            return (result, total, index)
        }
        return scored.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            let (a, b) = (counts[$0.result.id] ?? 0, counts[$1.result.id] ?? 0)
            return a != b ? a > b : $0.index < $1.index
        }.map(\.result)
    }

    private static func flatten(_ nodes: [LibraryItem], folder: String) -> [QuickOpenResult] {
        nodes.flatMap { node -> [QuickOpenResult] in
            if let children = node.children {
                return flatten(children, folder: folder.isEmpty ? node.name : "\(folder) / \(node.name)")
            }
            return node.isOpenable ? [QuickOpenResult(kind: .item(node, folder: folder), id: node.id.uuidString)] : []
        }
    }

    private static func isSubsequence(_ word: String, of text: String) -> Bool {
        var remaining = word[...]
        for char in text where char == remaining.first {
            remaining = remaining.dropFirst()
        }
        return remaining.isEmpty
    }

    /// The web link in what was typed, if it is one: a full URL, or a host name such as `example.com/path`.
    static func link(from query: String) -> URL? {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if text.contains("://") {
            return URL(string: text).flatMap { $0.host == nil ? nil : $0 }
        }
        guard let url = URL(string: "https://\(text)"), let host = url.host,
              let last = host.split(separator: ".").last, host.contains("."),
              last.count >= 2, last.allSatisfy(\.isLetter) else { return nil }
        return url
    }
}

struct QuickOpenAction: Identifiable {
    let id: String
    let title: String
    let run: @MainActor () -> Void
}
