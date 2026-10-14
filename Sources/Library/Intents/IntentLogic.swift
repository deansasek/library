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
        "Run “\(node.name)” in Terminal? The command is:\n\n\(node.command ?? "")"
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
}
