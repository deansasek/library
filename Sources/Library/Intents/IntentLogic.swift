import Foundation

/// The rules behind the App Intents, kept apart from AppIntents so the checks can test them without Shortcuts.
enum IntentLogic {
    /// True for a bookmark or app the intents may open. Terminal commands are never opened by an intent that
    /// skips confirmation, so they are left out of search and suggestions.
    static func isLaunchable(_ node: LibraryItem) -> Bool {
        node.command == nil && node.isOpenable
    }

    /// Bookmarks and apps that match `query`, best matches first, as Quick Open orders them.
    static func launchables(matching query: String, in nodes: [LibraryItem], counts: [String: Int]) -> [LibraryItem] {
        QuickOpenResult.search(query, in: nodes, counts: counts)
            .compactMap(\.node)
            .filter(isLaunchable)
    }

    /// Terminal commands in the library, in display order.
    static func commands(in nodes: [LibraryItem]) -> [LibraryItem] {
        nodes.leaves.filter(canRunCommand)
    }

    /// Commands with text to run. A command that is only spaces does nothing, so it is not offered.
    static func canRunCommand(_ node: LibraryItem) -> Bool {
        guard let command = node.command else { return false }
        return !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The question shown before a command runs. It always names the command in full.
    static func confirmation(for node: LibraryItem) -> String {
        String(format: String(localized: "Run “%@” in Terminal? The command is:", bundle: L10n.bundle), node.name) + "\n\n" + (node.command ?? "")
    }

    /// A bookmark for a web link, named by its host. Nil for text that is not a link.
    static func bookmark(from text: String) -> LibraryItem? {
        guard let link = QuickOpenResult.link(from: text), let host = link.host else { return nil }
        return LibraryItem(name: host, url: link.absoluteString)
    }

    /// An app item for an `.app` bundle. Nil for any other file.
    static func app(atPath path: String) -> LibraryItem? {
        guard URL(fileURLWithPath: path).pathExtension.lowercased() == "app" else { return nil }
        return LibraryItem(name: appName(at: path), appPath: path)
    }

    /// True for an app directly inside /Applications or ~/Applications. An intent adds these without asking. A symbolic
    /// link does not count, since it can point anywhere. The folder is resolved, so the folder itself is compared as a real path.
    static func isStandardApplication(atPath path: String, home: String = NSHomeDirectory()) -> Bool {
        let url = URL(fileURLWithPath: path)
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil { return false }
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
        let folders = ["/Applications", home + "/Applications"].map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path }
        return folders.contains(parent)
    }

    /// The question shown before an app outside the Applications folders is added through an intent.
    static func addConfirmation(for node: LibraryItem) -> String {
        String(format: String(localized: "Add “%@” to Library? It is outside the Applications folders.", bundle: L10n.bundle), node.name)
    }

    /// Launching an app that an intent added asks first, every time.
    static func needsLaunchConfirmation(_ node: LibraryItem) -> Bool {
        node.appPath != nil && node.addedByIntent == true
    }
}
