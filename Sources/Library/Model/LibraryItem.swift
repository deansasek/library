import SwiftUI

/// A bookmark (`url`), an application (`appPath`), a terminal command (`command`),
/// a folder (`children`), or a titled divider (`isDivider`).
struct LibraryItem: Codable, Identifiable, Equatable {
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
    /// When the item was deleted. Set only on the top-level items in Recently Deleted, which are removed for good
    /// 30 days later.
    var deletedDate: Date?
    /// The folder the item was in when it was deleted, so Restore can put it back there.
    var deletedFrom: UUID?
    /// The named fields a URL template declares in Get Info, each "name" or "name:Label". Only declared names are
    /// placeholders, so `{name}` is plain text in a URL without them. Nil for templates that use only `{}`.
    var templateFields: [String]?
    /// A note about the item, in plain text, which may span lines. Quick Open and Spotlight show it. Nil when empty.
    var note: String?
    /// Whether a bookmark is in the Reading List, and read or unread there. Nil when it is not in the list.
    var readLater: ReadLaterState?
    /// What the last link check found, and when. Nil until a check runs, so files written before the check decode unchanged.
    var linkStatus: LinkStatus?
    /// Whether a folder's menus show its Open All item. Nil means shown, so files written before this setting decode unchanged.
    var showsOpenAll: Bool?

    /// True when a folder's menus show Open All. Nil counts as shown.
    var showsOpenAllItem: Bool { showsOpenAll ?? true }

    var isFolder: Bool { children != nil }

    static let tagNames = ["red", "orange", "yellow", "green", "blue", "purple", "gray"]
    static let tagColors: [String: NSColor] = [
        "red": .systemRed, "orange": .systemOrange, "yellow": .systemYellow, "green": .systemGreen,
        "blue": .systemBlue, "purple": .systemPurple, "gray": .systemGray,
    ]

    /// The color tag as VoiceOver reads it, such as "red tag". Nil for an item without a color. The dot alone is not
    /// enough, because VoiceOver cannot see it.
    static func tagAccessibilityName(_ color: String?) -> String? {
        guard let color, tagColors[color] != nil else { return nil }
        let name: String
        switch color {
        case "red": name = String(localized: "red", bundle: L10n.bundle)
        case "orange": name = String(localized: "orange", bundle: L10n.bundle)
        case "yellow": name = String(localized: "yellow", bundle: L10n.bundle)
        case "green": name = String(localized: "green", bundle: L10n.bundle)
        case "blue": name = String(localized: "blue", bundle: L10n.bundle)
        case "purple": name = String(localized: "purple", bundle: L10n.bundle)
        default: name = String(localized: "gray", bundle: L10n.bundle)
        }
        return String(format: String(localized: "%@ tag", bundle: L10n.bundle), name)
    }

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

    /// The note with surrounding whitespace removed. Nil when there is no note.
    var noteText: String? { Self.cleanNote(note) }

    /// Trims a note and returns nil when nothing is left, so an empty note is stored as no note.
    static func cleanNote(_ text: String?) -> String? {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// What Spotlight shows as the description: the target, then the note on the next line.
    var spotlightDescription: String? {
        let target = url ?? command ?? appPath
        let parts = [target, noteText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    /// Only bookmarks with a fixed link can be in the Reading List. A template would ask for a value each time.
    var canReadLater: Bool { url != nil && !isTemplate }

    /// True for items that open something, so they can have a shortcut.
    var isOpenable: Bool { url != nil || appPath != nil || command != nil }

    /// True when the URL has a placeholder (`{}`, or a declared `{name}` or `{name:Label}`) that is filled in when opening.
    var isTemplate: Bool { !placeholders.isEmpty }

    /// The distinct values the URL asks for, in order. Empty when the URL is not a template.
    var placeholders: [TemplateField] { templateFieldList(in: url ?? "", declared: templateFields) }

    /// The URL to open, with every placeholder left empty. Adds `https://` when the scheme is missing.
    var link: URL? { link(filling: "") }

    /// The URL to open with every placeholder replaced by the percent-encoded `value`.
    func link(filling value: String) -> URL? {
        link(values: Dictionary(placeholders.map { ($0.name, value) }, uniquingKeysWith: { first, _ in first }))
    }

    /// The URL to open with each placeholder replaced by the percent-encoded value for its name. Nil when a
    /// placeholder has no value, or when nothing is left to open.
    func link(values: [String: String]) -> URL? {
        guard let filled = fillTemplate(url ?? "", declared: templateFields, values: values) else { return nil }
        let trimmed = filled.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: hasScheme(trimmed) ? trimmed : "https://\(trimmed)")
    }

    /// True when the text starts with a URL scheme, such as mailto:, tel:, or obsidian://. A host and port such as
    /// localhost:8080 is not a scheme, so it still gets https:// in front.
    private func hasScheme(_ text: String) -> Bool {
        guard let colon = text.firstIndex(of: ":") else { return false }
        let scheme = text[..<colon]
        guard let first = scheme.first, first.isLetter,
              scheme.allSatisfy({ $0.isLetter || $0.isNumber || "+-.".contains($0) }) else { return false }
        return !(text[text.index(after: colon)...].first?.isNumber ?? false)
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

/// The placeholders of `url` that are fields, in order. `{}` is always a field. A named one, `{name}` or
/// `{name:Label}`, is a field only when `declared` names it, so other braces stay plain text. Braces that never
/// close, or that enclose another `{`, are plain text too.
private func placeholderTokens(in url: String, declared: [String]?) -> [PlaceholderToken] {
    let names = Set((declared ?? []).map { splitDeclaredField($0).name })
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
        if name.isEmpty || names.contains(name) {
            tokens.append(PlaceholderToken(range: open..<url.index(after: close), name: name, label: label.isEmpty ? nil : label))
        }
        index = url.index(after: close)
    }
    return tokens
}

/// The name and label of one declared field, such as "query:Search terms". The label is empty when none is given.
private func splitDeclaredField(_ text: String) -> (name: String, label: String) {
    let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    let name = parts[0].trimmingCharacters(in: .whitespaces)
    let label = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
    return (name, label)
}

/// The fields Get Info declares, from its Fields text: comma-separated names, each with an optional label after a
/// colon, such as "query:Search terms, sort". Empty names and repeated names are dropped, and the first one wins.
/// Nil when nothing is left, so the URL has no named fields.
func parseTemplateFields(_ text: String) -> [String]? {
    var seen = Set<String>()
    var fields: [String] = []
    for part in text.split(separator: ",") {
        let (name, label) = splitDeclaredField(String(part))
        guard !name.isEmpty, !name.contains(where: { "{}".contains($0) }), seen.insert(name).inserted else { continue }
        fields.append(label.isEmpty ? name : name + ":" + label)
    }
    return fields.isEmpty ? nil : fields
}

/// The distinct fields `url` asks for, in the order they first appear. A name that repeats shares one field. Its
/// label is the one declared for it, or else the first label the URL gives it.
func templateFieldList(in url: String, declared: [String]? = nil) -> [TemplateField] {
    var declaredLabels: [String: String] = [:]
    for field in declared ?? [] {
        let (name, label) = splitDeclaredField(field)
        if declaredLabels[name] == nil { declaredLabels[name] = label }
    }
    var fields: [TemplateField] = []
    for token in placeholderTokens(in: url, declared: declared) {
        let declaredLabel = declaredLabels[token.name].flatMap { $0.isEmpty ? nil : $0 }
        if let index = fields.firstIndex(where: { $0.name == token.name }) {
            if fields[index].label == nil, let label = declaredLabel ?? token.label {
                fields[index] = TemplateField(name: token.name, label: label)
            }
        } else {
            fields.append(TemplateField(name: token.name, label: declaredLabel ?? token.label))
        }
    }
    return fields
}

/// `url` with each placeholder replaced by `text(name)`. Nil when `text` returns nil for a name.
private func replacePlaceholders(in url: String, declared: [String]?, _ text: (String) -> String?) -> String? {
    var result = ""
    var last = url.startIndex
    for token in placeholderTokens(in: url, declared: declared) {
        guard let replacement = text(token.name) else { return nil }
        result += String(url[last..<token.range.lowerBound]) + replacement
        last = token.range.upperBound
    }
    return result + String(url[last...])
}

/// `url` with each placeholder replaced by the percent-encoded value for its name. Nil when a name has no value.
/// Values are encoded the same way for every placeholder: only unreserved characters pass through.
func fillTemplate(_ url: String, declared: [String]? = nil, values: [String: String]) -> String? {
    let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    return replacePlaceholders(in: url, declared: declared) { name in
        values[name].map { $0.addingPercentEncoding(withAllowedCharacters: unreserved) ?? $0 }
    }
}

/// `url` with every placeholder removed.
func withoutPlaceholders(_ url: String, declared: [String]? = nil) -> String {
    replacePlaceholders(in: url, declared: declared) { _ in "" } ?? url
}

/// `url` with each placeholder shown as ‹label› for the edit sheet's preview.
func templatePreview(_ url: String, declared: [String]? = nil) -> String {
    let fields = templateFieldList(in: url, declared: declared)
    return replacePlaceholders(in: url, declared: declared) { name in
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
