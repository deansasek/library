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
        /// A saved snippet. Return copies its text.
        case snippet(Snippet)
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
        case .item, .clip, .snippet, .openLink, .addLink: return true
        default: return false
        }
    }

    var title: String {
        switch kind {
        case .answer(let value, _): return value
        case .addSuggestion(let suggestion): return suggestion.title
        case .clip(let item): return item.title
        case .item(let node, _): return node.name
        case .snippet(let snippet): return snippet.name
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
        case .snippet(let snippet): return snippet.text.split(whereSeparator: \.isNewline).joined(separator: " ")
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
///
/// Two things make typing cheap, and neither changes the result:
/// - Bytes. Text and words that are plain ASCII are also kept as UTF-8 bytes, and matched with byte loops instead
///   of String comparisons. Anything else (a non-ASCII character, or a carriage return, whose two-character grapheme
///   the byte loops would split) keeps the String comparison, decided per item and per word. So the byte path only
///   runs where it gives the same answer as the String one.
/// - Narrowing. A query that extends the previous one (more words, or more letters on its last word) can only match
///   what the previous query matched: every clause that matches "ab" also matches "a". The index keeps the previous
///   query and its matches, and a query that extends it searches only those. Any other change (a backspace, a word
///   removed) searches the whole library.
final class QuickOpenIndex {
    /// The lowercased text of an item as plain ASCII bytes. Nil when any part of it needs the String path.
    private struct Bytes {
        let name: [UInt8]
        let keywords: [[UInt8]]
        let other: [UInt8]
    }

    private struct Entry {
        let result: QuickOpenResult
        let name: String
        let keywords: [String]
        /// Target, folder, and keywords: the text matched after the name.
        let other: String
        let bytes: Bytes?
    }

    /// A lowercased word of the query. Its bytes are nil when it is not plain ASCII.
    private struct Word {
        let text: String
        let bytes: [UInt8]?
    }

    private struct Hit {
        let index: Int
        let score: Int
    }

    private let entries: [Entry]
    /// What an empty query shows: the library as the menu shows it, items under their dividers.
    private let browse: [QuickOpenResult]
    /// The last query that had words, and the indices of the entries that matched all of them, in index order.
    private var previous: (words: [String], matches: [Int])?

    /// `snippets` are matched by name and keywords, like items. They are not in the browse list.
    init(nodes: [LibraryItem], snippets: [Snippet] = []) {
        browse = nodes.sections.flatMap { section -> [QuickOpenResult] in
            var items = Self.leaves(section.nodes, folder: "").map(Self.row)
            if !items.isEmpty { items[0].section = section.title ?? "Library" }
            return items
        }
        let items = Self.leaves(nodes, folder: "").map { leaf -> Entry in
            let node = leaf.node
            let keywords = "\(node.keywords ?? "") \(node.color ?? "")".lowercased().split(separator: " ").map(String.init)
            let other = "\(node.url ?? "") \(node.command ?? "") \(node.appPath ?? "") \(leaf.folder) \(keywords.joined(separator: " "))".lowercased()
            let name = node.name.lowercased()
            return Entry(result: Self.row(leaf), name: name, keywords: keywords, other: other,
                         bytes: Self.bytes(name: name, keywords: keywords, other: other))
        }
        let saved = snippets.map { snippet -> Entry in
            let keywords = (snippet.keywords ?? "").lowercased().split(separator: " ").map(String.init)
            let other = keywords.joined(separator: " ")
            let name = snippet.name.lowercased()
            return Entry(result: QuickOpenResult(kind: .snippet(snippet), id: "snippet-\(snippet.id.uuidString)"),
                         name: name, keywords: keywords, other: other, bytes: Self.bytes(name: name, keywords: keywords, other: other))
        }
        entries = items + saved
    }

    /// Items that match every word of `query` in the name, keywords, target, or folder. Best matches first,
    /// then the most opened. An empty query lists the library as the menu shows it.
    func search(_ query: String, counts: [String: Int]) -> [QuickOpenResult] {
        let words = Self.words(query)
        if words.isEmpty {
            previous = nil
            return browse
        }
        let texts = words.map(\.text)
        let hits: [Hit]
        if let previous, Self.extends(texts, previous.words) {
            hits = matches(words, among: previous.matches)
        } else {
            hits = matches(words, among: nil)
        }
        previous = (texts, hits.map(\.index))
        // Each count is read once, not once per comparison.
        return hits.map { hit in
            (result: entries[hit.index].result, score: hit.score, index: hit.index,
             count: counts[entries[hit.index].result.id] ?? 0)
        }.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.count != $1.count ? $0.count > $1.count : $0.index < $1.index
        }.map(\.result)
    }

    /// The entries that match every word, with their total score, in index order. `pool` limits the search to
    /// the given indices, and nil searches the whole library.
    private func matches(_ words: [Word], among pool: [Int]?) -> [Hit] {
        var hits: [Hit] = []
        if let pool {
            for index in pool {
                if let score = Self.total(words, entries[index]) { hits.append(Hit(index: index, score: score)) }
            }
        } else {
            for index in entries.indices {
                if let score = Self.total(words, entries[index]) { hits.append(Hit(index: index, score: score)) }
            }
        }
        return hits
    }

    /// The sum of the word scores, or nil when one word does not match.
    private static func total(_ words: [Word], _ entry: Entry) -> Int? {
        var total = 0
        for word in words {
            let score = score(word, in: entry)
            if score == 0 { return nil }
            total += score
        }
        return total
    }

    /// 4 for a prefix of the name or a keyword, 3 inside the name, 1 for letters in order within the name, 2 for
    /// the target, folder, or keywords, and 0 for no match.
    private static func score(_ word: Word, in entry: Entry) -> Int {
        if let wordBytes = word.bytes, let bytes = entry.bytes {
            if bytesHavePrefix(bytes.name, wordBytes) || bytes.keywords.contains(where: { bytesHavePrefix($0, wordBytes) }) {
                return 4
            }
            if bytesContain(bytes.name, wordBytes) { return 3 }
            if bytesSubsequence(wordBytes, of: bytes.name) { return 1 }
            return bytesContain(bytes.other, wordBytes) ? 2 : 0
        }
        if entry.name.hasPrefix(word.text) || entry.keywords.contains(where: { $0.hasPrefix(word.text) }) { return 4 }
        if entry.name.contains(word.text) { return 3 }
        if isSubsequence(word.text, of: entry.name) { return 1 }
        return entry.other.contains(word.text) ? 2 : 0
    }

    /// True when `words` is `previous` with words added, or with its last word extended. Then every entry that
    /// matches `words` also matches `previous`, so the search can start from the previous matches.
    private static func extends(_ words: [String], _ previous: [String]) -> Bool {
        guard let last = previous.last, words.count >= previous.count else { return false }
        for index in previous.indices.dropLast() where words[index] != previous[index] { return false }
        return words[previous.count - 1].hasPrefix(last)
    }

    /// The lowercased words of a query, as Quick Open splits them: on spaces, with empty pieces dropped.
    private static func words(_ query: String) -> [Word] {
        query.lowercased().split(separator: " ").map { piece in
            let text = String(piece)
            return Word(text: text, bytes: plain(text))
        }
    }

    /// The UTF-8 bytes of `text` when it is plain ASCII without a carriage return, else nil.
    private static func plain(_ text: String) -> [UInt8]? {
        let bytes = Array(text.utf8)
        return bytes.allSatisfy { $0 < 0x80 && $0 != 0x0D } ? bytes : nil
    }

    private static func bytes(name: String, keywords: [String], other: String) -> Bytes? {
        guard let nameBytes = plain(name), let otherBytes = plain(other) else { return nil }
        var keywordBytes: [[UInt8]] = []
        for keyword in keywords {
            guard let bytes = plain(keyword) else { return nil }
            keywordBytes.append(bytes)
        }
        return Bytes(name: nameBytes, keywords: keywordBytes, other: otherBytes)
    }

    private static func bytesHavePrefix(_ text: [UInt8], _ prefix: [UInt8]) -> Bool {
        guard prefix.count <= text.count else { return false }
        for index in prefix.indices where text[index] != prefix[index] { return false }
        return true
    }

    private static func bytesContain(_ text: [UInt8], _ word: [UInt8]) -> Bool {
        guard let first = word.first, word.count <= text.count else { return word.isEmpty }
        for start in 0...(text.count - word.count) where text[start] == first {
            var offset = 1
            while offset < word.count && text[start + offset] == word[offset] { offset += 1 }
            if offset == word.count { return true }
        }
        return false
    }

    private static func bytesSubsequence(_ word: [UInt8], of text: [UInt8]) -> Bool {
        var matched = 0
        for byte in text where matched < word.count && byte == word[matched] { matched += 1 }
        return matched == word.count
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
