import AppKit

/// File > Import Bookmarks…. The user picks the browser's bookmarks file, and the import lands as one undoable folder.
/// Panels and alerts attach to the window in front as sheets (see `Sheets`).
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
        AttachedSheets.choose(panel) { url in
            guard let url else { return }
            importFile(at: url, into: store)
        }
    }

    private static func importFile(at url: URL, into store: LibraryStore) {
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
        guard BookmarkImport.isAlreadyImported(folder, in: store.nodes) else {
            add(folder, result, to: store)
            return
        }
        confirmImportAgain(url.lastPathComponent) { again in
            guard again else { return }
            add(folder, result, to: store)
        }
    }

    private static func add(_ folder: LibraryItem, _ result: BookmarkImport.Result, to store: LibraryStore) {
        store.perform("Import Bookmarks") { $0.append(folder) }

        let count = "\(result.imported) \(result.imported == 1 ? "bookmark" : "bookmarks")"
        var details = "They are in the folder “\(folder.name)”."
        if result.skipped > 0 {
            details += " Skipped \(result.skipped) \(result.skipped == 1 ? "entry" : "entries") that aren’t web links."
        }
        report("Imported \(count)", details, style: .informational)
    }

    /// Asks before a second copy of bookmarks that are all saved already. `completion` gets true when the user chooses to import again.
    private static func confirmImportAgain(_ fileName: String, completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "These bookmarks are already in your library"
        alert.informativeText = "Every web link in “\(fileName)” is saved already. Importing again adds a second copy of each."
        alert.addButton(withTitle: "Import Again")
        alert.addButton(withTitle: "Cancel")
        AttachedSheets.alert(alert) { response in
            completion(response == .alertFirstButtonReturn)
        }
    }

    private static func report(_ message: String, _ details: String, style: NSAlert.Style = .warning) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = message
        alert.informativeText = details
        AttachedSheets.alert(alert)
    }
}
