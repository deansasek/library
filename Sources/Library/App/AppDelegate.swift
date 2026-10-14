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
        if UserDefaults.standard.bool(forKey: "reenableLoginItemAfterMove") {
            UserDefaults.standard.removeObject(forKey: "reenableLoginItemAfterMove")
            LoginItem.shared.set(true)
        }
        if UserDefaults.standard.bool(forKey: "resumeWelcomeAfterMove") {
            // Library was just moved to Applications. Show the last page of the tour, with its check mark.
            UserDefaults.standard.removeObject(forKey: "resumeWelcomeAfterMove")
            Welcome.show(store: LibraryStore.shared, page: WelcomeModel.pageCount - 1)
        } else if LibraryStore.shared.hadUnreadableFile {
            DispatchQueue.main.async { Self.reportUnreadableFile() }
        } else {
            Welcome.showIfNeeded(store: LibraryStore.shared)
        }
        // macOS marks a login launch in the launch event. Right after boot also counts, in case it does not.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let byLoginItem = event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
            == OSType(keyAELaunchedAsLogInItem)
        if byLoginItem || ProcessInfo.processInfo.systemUptime < 120 {
            openLoginItems()
        }
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
        alert.messageText = "Library Can’t Read bookmarks.json"
        alert.informativeText = "The file may have been edited into something Library doesn’t understand. A copy was saved as bookmarks-damaged.json, and Library started with an empty library. Your next change replaces bookmarks.json."
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([LibraryStore.dir.appendingPathComponent("bookmarks-damaged.json")])
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        LibraryStore.shared.flushSave()
    }

    /// `library://open?name=Jira&value=ABC-123` opens an item and fills its template.
    /// `library://menu` shows the menu. `library://search` shows Quick Open.
    func application(_ application: NSApplication, open urls: [URL]) {
        let store = LibraryStore.shared
        for url in urls where url.scheme == "library" {
            if url.host == "menu" {
                store.showMenu()
                continue
            }
            if url.host == "search" {
                store.showQuickOpen()
                continue
            }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
            if url.host == "open", let name = value("name"),
               let node = store.nodes.leaves.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                open(node, value: value("value"))
            }
        }
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
        guard let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: text), let host = url.host, url.scheme?.hasPrefix("http") == true else {
            error.pointee = "The selection is not a web link."
            return
        }
        LibraryStore.shared.perform("Add Bookmark") {
            $0.append(LibraryItem(name: host, url: text), to: nil)
        }
    }
}
