import AppKit
import UniformTypeIdentifiers

/// File > Export Library… and Settings > Backup. Writes and reads the files that `LibraryBackup` encodes and decodes.
@MainActor
enum LibraryBackupActions {
    static let exportNote = "The backup has your bookmarks, folders, shortcuts, icons, keywords, colors, templates, and Open at login settings. It doesn’t include clipboard items. Pinned clipboard items are encrypted with a key that stays on this Mac, so they aren’t exported."

    static func export(_ store: LibraryStore) {
        let panel = NSSavePanel()
        panel.message = exportNote
        panel.prompt = "Export"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Library Backup \(dateStamp()).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let data: Data
        do {
            data = try LibraryBackup.encode(store.nodes)
        } catch {
            return report("Couldn’t export the library", error.localizedDescription)
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            report("Couldn’t export the library", "Library couldn’t write “\(url.lastPathComponent)”. \(error.localizedDescription)")
        }
    }

    static func restore(_ store: LibraryStore) {
        // Changes cannot be saved while bookmarks.json is unreadable, so a restore would be lost. Refuse it first.
        guard !store.fileReadFailed else {
            return report("Can’t restore right now", "bookmarks.json can’t be read, so a restored library couldn’t be saved. Fix the file’s permissions, then try again.")
        }
        let panel = NSOpenPanel()
        panel.message = "Choose a Library backup. Restoring replaces your current library. You can undo the restore with Undo."
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let items: [LibraryItem]
        do {
            let data = try Data(contentsOf: url)
            switch LibraryBackup.decode(data) {
            case .success(let decoded):
                items = LibraryBackup.restorable(decoded, avoiding: store.deleted)
            case .failure(let error):
                return report("Couldn’t restore the library", "“\(url.lastPathComponent)” couldn’t be restored. \(error.message)")
            }
        } catch {
            return report("Couldn’t restore the library", "Library couldn’t open “\(url.lastPathComponent)”.")
        }

        let current = store.nodes.allIDs.count
        let incoming = items.allIDs.count
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Replace your library?"
        alert.informativeText = "Your library has \(count(current)). It will be replaced by the \(count(incoming)) in “\(url.lastPathComponent)”. Undo restores the current library."
        alert.addButton(withTitle: "Cancel")
        let replace = alert.addButton(withTitle: "Replace Library")
        replace.hasDestructiveAction = true
        // Cancel is the default button, so pressing Return keeps the library.
        guard alert.runModal() == .alertSecondButtonReturn else { return }

        store.perform("Restore Library") { $0 = items }
    }

    private static func count(_ n: Int) -> String {
        "\(n) \(n == 1 ? "item" : "items")"
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func report(_ message: String, _ details: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = details
        alert.runModal()
    }
}
