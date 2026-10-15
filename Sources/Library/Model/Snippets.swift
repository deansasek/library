import SwiftUI

/// A saved piece of text, such as an address or a standard reply. Quick Open copies it. Snippets are kept in
/// snippets.json, not in clipboard history, so they are not encrypted.
struct Snippet: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var text: String
    /// Extra words that find the snippet in Quick Open, separated by spaces.
    var keywords: String?

    /// This edit's changes, compared with `base`, applied to `current`. A field this edit did not change keeps the
    /// value in `current`.
    func applying(changesFrom base: Snippet, to current: Snippet) -> Snippet {
        var result = current
        if name != base.name { result.name = name }
        if text != base.text { result.text = text }
        if keywords != base.keywords { result.keywords = keywords }
        return result
    }
}

/// The saved snippets, in snippets.json in the library folder.
@MainActor
final class SnippetStore: ObservableObject {
    static let shared = SnippetStore()
    static let defaultFile = LibraryStore.dir.appendingPathComponent("snippets.json")

    @Published private(set) var snippets: [Snippet] = []
    /// True when snippets.json exists but cannot be read. Nothing is changed or written over it until it can be read,
    /// so add, update, and remove do nothing and the Manage window and the editor disable their save actions.
    @Published private(set) var saveBlocked = false
    private let file: URL?

    /// `file` is where the snippets are saved. Nil keeps them in memory only.
    init(file: URL? = SnippetStore.defaultFile) {
        self.file = file
        load()
    }

    private func load() {
        guard let file, FileManager.default.fileExists(atPath: file.path) else { return }
        guard let data = try? Data(contentsOf: file) else {
            NSLog("Library: could not read snippets.json, so changes to snippets are not saved")
            saveBlocked = true
            return
        }
        guard let loaded = try? JSONDecoder().decode([Snippet].self, from: data) else {
            // Like a damaged bookmarks.json: keep the file aside for inspection and start with no snippets.
            let damaged = file.deletingLastPathComponent().appendingPathComponent("snippets-damaged.json")
            try? FileManager.default.removeItem(at: damaged)
            try? FileManager.default.moveItem(at: file, to: damaged)
            NSLog("Library: snippets.json could not be read, so it was moved to snippets-damaged.json")
            return
        }
        snippets = loaded
    }

    func add(_ snippet: Snippet) {
        guard !saveBlocked else { return }
        snippets.append(snippet)
        save()
    }

    /// Saves an edit. `base` is the snippet as the editor opened it. Fields this edit did not change keep the value the
    /// stored snippet has now, so an edit made in another window is kept. Returns false, and changes nothing, when the
    /// snippet was removed or saving is blocked.
    @discardableResult
    func update(_ snippet: Snippet, changedFrom base: Snippet) -> Bool {
        guard !saveBlocked, let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return false }
        snippets[index] = snippet.applying(changesFrom: base, to: snippets[index])
        save()
        return true
    }

    func remove(_ ids: Set<UUID>) {
        guard !saveBlocked else { return }
        snippets.removeAll { ids.contains($0.id) }
        save()
    }

    private func save() {
        guard let file, !saveBlocked else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(snippets).write(to: file, options: .atomic)
        } catch {
            NSLog("Library could not save snippets.json: \(error.localizedDescription)")
        }
    }
}
