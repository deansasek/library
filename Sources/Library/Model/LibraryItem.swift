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

    /// True when the URL has a `{}` placeholder that is filled in when opening.
    var isTemplate: Bool { url?.contains("{}") == true }

    /// The URL to open, with the template left empty. Adds `https://` when the scheme is missing.
    var link: URL? { link(filling: "") }

    /// The URL to open with `{}` replaced by the percent-encoded `value`.
    func link(filling value: String) -> URL? {
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
        let trimmed = (url ?? "").replacingOccurrences(of: "{}", with: encoded).trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)")
    }

    /// True for this node or any node beneath it.
    func contains(_ id: UUID) -> Bool {
        self.id == id || (children?.contains { $0.contains(id) } ?? false)
    }
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
