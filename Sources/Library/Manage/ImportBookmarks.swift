import AppKit

/// File > Import Bookmarks…. The user picks the browser's bookmarks file, and the import lands as one undoable folder.
@MainActor
enum BookmarkImporter {
    static func run(into store: LibraryStore) {
        let panel = NSOpenPanel()
        panel.message = """
            Choose Bookmarks.plist in ~/Library/Safari for Safari, or the Bookmarks file in \
            ~/Library/Application Support/Google/Chrome/Default for Chrome. Press ⇧⌘G to type a path.
            """
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            report("Couldn’t Read the File", "Library couldn’t open “\(url.lastPathComponent)”.")
            return
        }

        let result: BookmarkImport.Result
        do {
            result = try BookmarkImport.parse(data)
        } catch {
            report("Couldn’t Import Bookmarks", "“\(url.lastPathComponent)” isn’t a Safari or Chrome bookmarks file.")
            return
        }

        guard result.imported > 0 else {
            report("No Bookmarks Found", "“\(url.lastPathComponent)” has no web bookmarks to import.")
            return
        }

        let folder = result.folder
        store.perform("Import Bookmarks") { $0.append(folder) }

        let count = "\(result.imported) \(result.imported == 1 ? "bookmark" : "bookmarks")"
        var details = "They are in the folder “\(folder.name)”."
        if result.skipped > 0 {
            details += " Skipped \(result.skipped) \(result.skipped == 1 ? "entry" : "entries") that aren’t web links."
        }
        report("Imported \(count)", details, style: .informational)
    }

    private static func report(_ message: String, _ details: String, style: NSAlert.Style = .warning) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = message
        alert.informativeText = details
        alert.runModal()
    }
}
