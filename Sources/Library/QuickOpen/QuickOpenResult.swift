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
    /// Builds the index for `nodes` and searches it once. The model keeps an index instead, so typing does not
    /// rebuild it. See `QuickOpenIndex.search` for the ranking.
    static func search(_ query: String, in nodes: [LibraryItem], counts: [String: Int]) -> [QuickOpenResult] {
        QuickOpenIndex(nodes: nodes).search(query, counts: counts)
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

/// The library's openable items, prepared for Quick Open. Names are lowercased and the text each item is matched
/// against is joined once, so a keystroke only scores these entries. Build a new index when the library changes.
struct QuickOpenIndex {
    private struct Entry {
        let result: QuickOpenResult
        let name: String
        let keywords: [String]
        /// Target, folder, and keywords: the text matched after the name.
        let other: String
    }

    private let entries: [Entry]
    /// What an empty query shows: the library as the menu shows it, items under their dividers.
    private let browse: [QuickOpenResult]

    init(nodes: [LibraryItem]) {
        browse = nodes.sections.flatMap { section -> [QuickOpenResult] in
            var items = Self.leaves(section.nodes, folder: "").map(Self.row)
            if !items.isEmpty { items[0].section = section.title ?? "Library" }
            return items
        }
        entries = Self.leaves(nodes, folder: "").map { leaf in
            let node = leaf.node
            let keywords = "\(node.keywords ?? "") \(node.color ?? "")".lowercased().split(separator: " ").map(String.init)
            let other = "\(node.url ?? "") \(node.command ?? "") \(node.appPath ?? "") \(leaf.folder) \(keywords.joined(separator: " "))".lowercased()
            return Entry(result: Self.row(leaf), name: node.name.lowercased(), keywords: keywords, other: other)
        }
    }

    /// Items that match every word of `query` in the name, keywords, target, or folder. Best matches first,
    /// then the most opened. An empty query lists the library as the menu shows it.
    func search(_ query: String, counts: [String: Int]) -> [QuickOpenResult] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        if words.isEmpty { return browse }
        var scored: [(result: QuickOpenResult, score: Int, index: Int)] = []
        for (index, entry) in entries.enumerated() {
            var total = 0
            var matches = true
            for word in words {
                let score = Self.score(word, in: entry)
                if score == 0 {
                    matches = false
                    break
                }
                total += score
            }
            if matches { scored.append((entry.result, total, index)) }
        }
        return scored.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            let (a, b) = (counts[$0.result.id] ?? 0, counts[$1.result.id] ?? 0)
            return a != b ? a > b : $0.index < $1.index
        }.map(\.result)
    }

    /// 4 for a prefix of the name or a keyword, 3 inside the name, 1 for letters in order within the name, 2 for
    /// the target, folder, or keywords, and 0 for no match.
    private static func score(_ word: String, in entry: Entry) -> Int {
        if entry.name.hasPrefix(word) || entry.keywords.contains(where: { $0.hasPrefix(word) }) { return 4 }
        if entry.name.contains(word) { return 3 }
        if isSubsequence(word, of: entry.name) { return 1 }
        return entry.other.contains(word) ? 2 : 0
    }

    private static func leaves(_ nodes: [LibraryItem], folder: String) -> [(node: LibraryItem, folder: String)] {
        nodes.flatMap { node -> [(node: LibraryItem, folder: String)] in
            if let children = node.children {
                return leaves(children, folder: folder.isEmpty ? node.name : "\(folder) / \(node.name)")
            }
            return node.isOpenable ? [(node, folder)] : []
        }
    }

    private static func row(_ leaf: (node: LibraryItem, folder: String)) -> QuickOpenResult {
        QuickOpenResult(kind: .item(leaf.node, folder: leaf.folder), id: leaf.node.id.uuidString)
    }

    private static func isSubsequence(_ word: String, of text: String) -> Bool {
        var remaining = word[...]
        for char in text where char == remaining.first {
            remaining = remaining.dropFirst()
        }
        return remaining.isEmpty
    }
}

struct QuickOpenAction: Identifiable {
    let id: String
    let title: String
    let run: @MainActor () -> Void
}
