import CoreSpotlight
import UniformTypeIdentifiers
import CoreServices
import SwiftUI

/// Entry points from outside the app: the `library://` URL scheme, Spotlight results, and the Services menu.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        _ = ClipboardHistory.shared  // starts watching the clipboard
        _ = ScreenCaptures.shared  // starts the Spotlight query for new screenshots and recordings, when on
        ClipPreviewSource.removeLeftovers()
        removeStaleCommandFiles()  // command files Terminal never opened, left by an earlier run
        _ = ClipboardLock.shared  // starts watching for sleep, so the pinned items lock
        if UserDefaults.standard.bool(forKey: "reenableLoginItemAfterMove") {
            UserDefaults.standard.removeObject(forKey: "reenableLoginItemAfterMove")
            LoginItem.shared.set(true)
        }
        if UserDefaults.standard.bool(forKey: "resumeWelcomeAfterMove") {
            // Library was just moved to Applications. Show the last page of the tour, with its check mark.
            UserDefaults.standard.removeObject(forKey: "resumeWelcomeAfterMove")
            Welcome.show(page: WelcomeModel.pageCount - 1)
        } else if LibraryStore.shared.cloudFileMissing {
            DispatchQueue.main.async { Self.reportCloudFileMissing() }
        } else if LibraryStore.shared.fileReadFailed {
            DispatchQueue.main.async { Self.reportReadFailure() }
        } else if LibraryStore.shared.hadUnreadableFile {
            DispatchQueue.main.async { Self.reportUnreadableFile() }
        } else {
            Welcome.showIfNeeded()
        }
        // macOS marks a login launch in the launch event. Only that launch opens the login items, so a manual launch
        // or a relaunch soon after boot does not open them a second time.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let byLoginItem = event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
            == OSType(keyAELaunchedAsLogInItem)
        if byLoginItem {
            openLoginItems()
        }
        UpdateCheck.start()
        LinkChecker.startSchedule()
    }

    /// Opens the items marked "Open When You Log In", a few seconds after login so the desktop is ready.
    /// Templates are skipped, since they would ask for a value.
    private func openLoginItems() {
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            for node in LibraryStore.shared.nodes.leaves where node.openAtLogin == true && !node.isTemplate {
                open(node)
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
    }

    /// Says that bookmarks.json could not be read, and offers to show the copy that was saved.
    private static func reportUnreadableFile() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Library Can’t Read bookmarks.json", bundle: L10n.bundle)
        let copyName = LibraryStore.shared.damagedCopy?.lastPathComponent ?? "bookmarks-damaged.json"
        alert.informativeText = String(localized: "The file may have been edited into something Library doesn’t understand. A copy was saved as \(copyName), and Library started with an empty library. Your next change replaces bookmarks.json.", bundle: L10n.bundle)
        alert.addButton(withTitle: String(localized: "Show in Finder", bundle: L10n.bundle))
        alert.addButton(withTitle: String(localized: "OK", bundle: L10n.bundle))
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([LibraryStore.shared.damagedCopy ?? LibraryStore.dir.appendingPathComponent(copyName)])
        }
    }

    /// Says that the library is linked to iCloud Drive and the iCloud copy is gone. Library changes nothing until it is back.
    private static func reportCloudFileMissing() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Library Can’t Find bookmarks.json in iCloud Drive", bundle: L10n.bundle)
        alert.informativeText = String(localized: "Your library is kept in iCloud Drive, and that copy is missing. It may have been removed on another Mac, or iCloud may still be downloading it. Library won’t change anything until the file is back.", bundle: L10n.bundle)
        alert.addButton(withTitle: String(localized: "OK", bundle: L10n.bundle))
        alert.runModal()
    }

    /// Says that bookmarks.json exists but cannot be read. Library leaves the file as it is.
    private static func reportReadFailure() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Library Can’t Read bookmarks.json", bundle: L10n.bundle)
        alert.informativeText = String(localized: "The file is there, but Library can’t open it, usually because of its permissions. Library won’t change it. Fix the file’s permissions, then open Library again.", bundle: L10n.bundle)
        alert.addButton(withTitle: String(localized: "Show in Finder", bundle: L10n.bundle))
        alert.addButton(withTitle: String(localized: "OK", bundle: L10n.bundle))
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([LibraryStore.file])
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        LibraryStore.shared.flushSave()
        ClipboardHistory.shared.flushHistory()
    }

    /// What a `library://` link asks Library to do. The scheme and the action are matched without regard to case,
    /// since a URL's scheme and host are case-insensitive (RFC 3986) and macOS hands the app whatever was typed.
    enum LinkAction: Equatable {
        case menu
        case search
        /// `open`, with the item's name and the value that fills a single-field template.
        case open(name: String?, value: String?)
    }

    /// The action a link asks for, or nil when the link is not a Library link or names an action Library does not
    /// have. Pure, so the checks can cover the forms a Shortcut or a script can send.
    static func linkAction(_ url: URL) -> LinkAction? {
        guard url.scheme?.lowercased() == "library" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        switch url.host?.lowercased() {
        case "menu": return .menu
        case "search": return .search
        case "open": return .open(name: value("name"), value: value("value"))
        default: return nil
        }
    }

    /// `library://open?name=Jira&value=ABC-123` opens an item and fills its template.
    /// `library://menu` shows the menu. `library://search` shows Quick Open.
    func application(_ application: NSApplication, open urls: [URL]) {
        let store = LibraryStore.shared
        for url in urls {
            switch Self.linkAction(url) {
            case .menu:
                store.showMenu()
            case .search:
                store.showQuickOpen()
            case .open(let name, let value):
                guard let name, let node = Self.item(named: name, in: store.nodes) else { continue }
                if linkOpenNeedsConfirmation(node, value: value), !confirmLinkOpen(node, value: value) { continue }
                open(node, value: value)
            case nil:
                continue
            }
        }
    }

    /// The bookmark or app a `library://open` link names. Terminal commands are left out: a web page can send a
    /// link, so a link must never run a command.
    static func item(named name: String, in nodes: [LibraryItem]) -> LibraryItem? {
        nodes.leaves.first { $0.command == nil && $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Opens the item behind a Spotlight result.
    func application(_ application: NSApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        guard userActivity.activityType == CSSearchableItemActionType,
              let id = (userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String).flatMap(UUID.init),
              let node = LibraryStore.shared.nodes.node(withID: id) else { return false }
        open(node)
        return true
    }

    /// Services menu item "Add to Library": turns a selected web link into a bookmark.
    @objc func addBookmark(_ pasteboard: NSPasteboard, userData: String,
                           error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pasteboard.string(forType: .string), let url = Self.webLink(from: text) else {
            error.pointee = "The selection is not a web link."
            return
        }
        guard let node = Self.newBookmark(from: text, existing: LibraryStore.shared.nodes) else { return }
        LibraryStore.shared.perform("Add Bookmark") { $0.append(node, to: nil) }
        SmartTitle.nameFromPage(node.id, url: url)
    }

    /// The bookmark a Services selection adds: nil when the selection is not a web link, or when the library already
    /// holds that link (http and https count as one, as in `AddSuggestion.matchKey`), so a repeat adds nothing.
    static func newBookmark(from text: String, existing: [LibraryItem]) -> LibraryItem? {
        guard let url = webLink(from: text), let host = url.host else { return nil }
        let node = LibraryItem(name: host, url: text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let key = AddSuggestion.matchKey(node) else { return nil }
        let known = existing.leaves.contains { AddSuggestion.matchKey($0) == key }
        return known ? nil : node
    }

    /// The web link a Services selection names: an `http` or `https` address, at most 4,096 characters. Other
    /// schemes are refused, so a selection cannot add an address that opens another app.
    static func webLink(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 4_096, let url = URL(string: trimmed), WebFetch.isWeb(url) else { return nil }
        return url
    }

    /// Services menu item "Add to Library" for files: adds applications and folders selected in Finder.
    @objc func addFiles(_ pasteboard: NSPasteboard, userData: String,
                        error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                          options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let (nodes, _) = Self.fileNodes(from: urls, existing: LibraryStore.shared.nodes)
        guard !nodes.isEmpty else {
            error.pointee = "Only applications and folders that aren't already in your library can be added."
            return
        }
        LibraryStore.shared.perform("Add to Library") { list in
            for node in nodes { list.append(node, to: nil) }
        }
    }

    /// Turns file URLs into library nodes: an app for each `.app` bundle, and a link to each other directory, which
    /// opens it in Finder. Skips apps already in `existing` (by path), folders already in `existing` (by link), and
    /// repeats within `urls`. Files that are neither are returned as `rejected`.
    static func fileNodes(from urls: [URL], existing: [LibraryItem]) -> (nodes: [LibraryItem], rejected: [URL]) {
        var knownApps = Set(existing.leaves.compactMap(\.appPath))
        var knownFolders = Set(existing.leaves.compactMap(\.url))
        var nodes: [LibraryItem] = []
        var rejected: [URL] = []
        for url in urls {
            let path = url.path
            if !url.isFileURL {
                rejected.append(url)
            } else if url.pathExtension == "app" {
                guard knownApps.insert(path).inserted else { continue }
                nodes.append(LibraryItem(name: appName(at: path), appPath: path))
            } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                let link = url.standardizedFileURL.absoluteString
                guard knownFolders.insert(link).inserted else { continue }
                nodes.append(LibraryItem(name: url.lastPathComponent, url: link, icon: "folder"))
            } else {
                rejected.append(url)
            }
        }
        return (nodes, rejected)
    }
}
