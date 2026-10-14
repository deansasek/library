import SwiftUI

/// A bookmark (`url`), an application (`appPath`), a terminal command (`command`),
/// a folder (`children`), or a titled divider (`isDivider`).
struct LibraryItem: Codable, Identifiable {
    var id = UUID()
    var name: String
    var url: String?
    var appPath: String?
    var arguments: String?
    var command: String?
    var children: [LibraryItem]?
    var isDivider: Bool?
    var shortcuts: [Shortcut]?
    /// Click behavior for bookmarks and apps: new window or instance instead of reusing one.
    var openNew: Bool?
    /// An SF Symbol name or a single emoji. Overrides the default icon.
    var icon: String?
    /// Bundle id of the browser that opens a bookmark. Nil uses the default browser.
    var browser: String?
    /// A Finder-style color tag, one of `tagNames`.
    var color: String?
    /// Open the item when the Mac starts, if Library opens at login.
    var openAtLogin: Bool?
    /// Extra words that find the item in Quick Open and Spotlight, separated by spaces.
    var keywords: String?
    /// Label for the value prompt of a URL template.
    var promptLabel: String?

    var isFolder: Bool { children != nil }

    static let tagNames = ["red", "orange", "yellow", "green", "blue", "purple", "gray"]
    static let tagColors: [String: NSColor] = [
        "red": .systemRed, "orange": .systemOrange, "yellow": .systemYellow, "green": .systemGreen,
        "blue": .systemBlue, "purple": .systemPurple, "gray": .systemGray,
    ]

    /// Names for the two open behaviors. Nil for items without a choice.
    var modeLabels: (existing: String, new: String)? {
        if appPath != nil { return ("Bring Forward", "New Instance") }
        // A folder link opens in Finder, so there is no tab or window to choose.
        if let url, !url.hasPrefix("file:") { return ("New Tab", "New Window") }
        return nil
    }

    /// A link or app file that can be shared or dragged into other apps. Nil for templates and commands.
    var shareURL: URL? {
        if let path = appPath { return URL(fileURLWithPath: path) }
        return isTemplate ? nil : link
    }

    /// True for items that open something, so they can have a shortcut.
    var isOpenable: Bool { url != nil || appPath != nil || command != nil }

    /// True when the URL has a placeholder (`{}`, `{name}`, or `{name:Label}`) that is filled in when opening.
    var isTemplate: Bool { !placeholders.isEmpty }

    /// The distinct values the URL asks for, in order. Empty when the URL is not a template.
    var placeholders: [TemplateField] { templateFields(in: url ?? "") }

    /// The URL to open, with every placeholder left empty. Adds `https://` when the scheme is missing.
    var link: URL? { link(filling: "") }

    /// The URL to open with every placeholder replaced by the percent-encoded `value`.
    func link(filling value: String) -> URL? {
        link(values: Dictionary(placeholders.map { ($0.name, value) }, uniquingKeysWith: { first, _ in first }))
    }

    /// The URL to open with each placeholder replaced by the percent-encoded value for its name. Nil when a
    /// placeholder has no value, or when nothing is left to open.
    func link(values: [String: String]) -> URL? {
        guard let filled = fillTemplate(url ?? "", values: values) else { return nil }
        let trimmed = filled.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)")
    }

    /// True for this node or any node beneath it.
    func contains(_ id: UUID) -> Bool {
        self.id == id || (children?.contains { $0.contains(id) } ?? false)
    }
}

/// One value a URL template asks for. The name is empty for a bare `{}`. The label is what the prompt shows, if given.
struct TemplateField: Equatable {
    let name: String
    let label: String?
}

/// A `{...}` placeholder in a URL, with its range in the URL.
private struct PlaceholderToken {
    let range: Range<String.Index>
    let name: String
    let label: String?
}

/// The placeholders of `url` in order. `{}` has no name, `{name}` has one, and `{name:Label}` adds a label. Braces
/// that never close, or that enclose another `{`, are plain text.
private func placeholderTokens(in url: String) -> [PlaceholderToken] {
    var tokens: [PlaceholderToken] = []
    var index = url.startIndex
    while let open = url[index...].firstIndex(of: "{") {
        let afterOpen = url.index(after: open)
        guard let close = url[afterOpen...].firstIndex(where: { $0 == "{" || $0 == "}" }) else { break }
        guard url[close] == "}" else {
            index = close
            continue
        }
        let parts = url[afterOpen..<close].split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let name = parts[0].trimmingCharacters(in: .whitespaces)
        let label = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        tokens.append(PlaceholderToken(range: open..<url.index(after: close), name: name, label: label.isEmpty ? nil : label))
        index = url.index(after: close)
    }
    return tokens
}

/// The distinct fields `url` asks for, in the order they first appear. A name that repeats shares one field, and the
/// first label given for it is kept.
func templateFields(in url: String) -> [TemplateField] {
    var fields: [TemplateField] = []
    for token in placeholderTokens(in: url) {
        if let index = fields.firstIndex(where: { $0.name == token.name }) {
            if fields[index].label == nil, let label = token.label {
                fields[index] = TemplateField(name: token.name, label: label)
            }
        } else {
            fields.append(TemplateField(name: token.name, label: token.label))
        }
    }
    return fields
}

/// `url` with each placeholder replaced by `text(name)`. Nil when `text` returns nil for a name.
private func replacePlaceholders(in url: String, _ text: (String) -> String?) -> String? {
    var result = ""
    var last = url.startIndex
    for token in placeholderTokens(in: url) {
        guard let replacement = text(token.name) else { return nil }
        result += String(url[last..<token.range.lowerBound]) + replacement
        last = token.range.upperBound
    }
    return result + String(url[last...])
}

/// `url` with each placeholder replaced by the percent-encoded value for its name. Nil when a name has no value.
/// Values are encoded the same way for every placeholder: only unreserved characters pass through.
func fillTemplate(_ url: String, values: [String: String]) -> String? {
    let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    return replacePlaceholders(in: url) { name in
        values[name].map { $0.addingPercentEncoding(withAllowedCharacters: unreserved) ?? $0 }
    }
}

/// `url` with every placeholder removed.
func withoutPlaceholders(_ url: String) -> String {
    replacePlaceholders(in: url) { _ in "" } ?? url
}

/// `url` with each placeholder shown as ‹label› for the edit sheet's preview.
func templatePreview(_ url: String) -> String {
    let fields = templateFields(in: url)
    return replacePlaceholders(in: url) { name in
        let field = fields.first { $0.name == name }
        return "‹\(field?.label ?? (name.isEmpty ? "value" : name))›"
    } ?? url
}

/// The items Open All opens for `nodes`, in display order, including folders inside them. Bookmarks whose URL needs
/// no value and apps that are still installed are kept. Commands are left out, so no command runs in bulk. Templates
/// are left out, since each would ask again. Dividers and folders are not items.
func openAllSelection(in nodes: [LibraryItem],
                      appExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [LibraryItem] {
    nodes.leaves.filter { node in
        if node.isDivider == true || node.command != nil { return false }
        if let path = node.appPath { return appExists(path) }
        return node.url != nil && !node.isTemplate && node.link != nil
    }
}

/// Open All asks first when it would open more items than this.
let openAllConfirmLimit = 5

/// True when Open All should ask before opening `count` items.
func needsOpenAllConfirmation(_ count: Int) -> Bool {
    count > openAllConfirmLimit
}

struct Folder: Identifiable {
    let id: UUID
    let title: String
}

extension Array where Element == LibraryItem {
    /// Runs `body` on the array that directly holds node `id`, with the node's index.
    @discardableResult
    mutating func locate(_ id: UUID, _ body: (inout [LibraryItem], Int) -> Void) -> Bool {
        if let index = firstIndex(where: { $0.id == id }) {
            body(&self, index)
            return true
        }
        for index in indices where self[index].children != nil {
            if self[index].children!.locate(id, body) {
                return true
            }
        }
        return false
    }

    mutating func update(_ id: UUID, _ change: (inout LibraryItem) -> Void) {
        locate(id) { change(&$0[$1]) }
    }

    @discardableResult
    mutating func removeNode(_ id: UUID) -> LibraryItem? {
        var removed: LibraryItem?
        locate(id) { removed = $0.remove(at: $1) }
        return removed
    }

    /// Appends to folder `folderID`, or to the top level when `nil`.
    mutating func append(_ node: LibraryItem, to folderID: UUID?) {
        if let folderID {
            update(folderID) { $0.children?.append(node) }
        } else {
            append(node)
        }
    }

    func node(withID id: UUID) -> LibraryItem? {
        for node in self {
            if node.id == id { return node }
            if let found = node.children?.node(withID: id) { return found }
        }
        return nil
    }

    /// Every id in the tree in display order, folders before their contents.
    var allIDs: [UUID] {
        flatMap { [$0.id] + ($0.children?.allIDs ?? []) }
    }

    /// Every bookmark and app in the tree, folders flattened away.
    var leaves: [LibraryItem] {
        flatMap { $0.children?.leaves ?? [$0] }
    }

    /// Every folder in the tree with its path as title. Skips folders in `ids` and their contents.
    func folders(skipping ids: Set<UUID> = [], path: String = "") -> [Folder] {
        flatMap { node -> [Folder] in
            guard let children = node.children, !ids.contains(node.id) else { return [] }
            let title = path + node.name
            return [Folder(id: node.id, title: title)]
                + children.folders(skipping: ids, path: title + " / ")
        }
    }

    /// Splits the list at each divider. Items before the first divider have no title.
    var sections: [(title: String?, nodes: [LibraryItem])] {
        var result: [(title: String?, nodes: [LibraryItem])] = []
        for node in self {
            if node.isDivider == true {
                result.append((node.name, []))
            } else {
                if result.isEmpty {
                    result.append((nil, []))
                }
                result[result.count - 1].nodes.append(node)
            }
        }
        return result
    }
}
