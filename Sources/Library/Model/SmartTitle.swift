import Foundation

/// Names a new bookmark from its page's title, when Settings > General turns it on. The bookmark is added at once
/// with its host as the name, and the title replaces the host when the page answers. A bookmark renamed meanwhile
/// keeps its name.
@MainActor
enum SmartTitle {
    /// The UserDefaults key of the Settings toggle. Off by default.
    static let key = "nameNewBookmarksFromPages"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    /// True when the address may be asked for its page. Only web addresses are asked for, and an address with a query
    /// is not: sign-in, unsubscribe, and confirmation links carry a single-use token there, and asking for the page
    /// could use it up.
    static func mayFetch(_ url: URL) -> Bool {
        WebFetch.isWeb(url) && url.query == nil
    }

    /// Asks for the page of a new bookmark, once, when the setting is on. See `mayFetch` for the addresses asked.
    static func nameFromPage(_ id: UUID, url: URL) {
        guard isOn, mayFetch(url), let host = url.host else { return }
        Task {
            guard let title = await PageTitle.fetch(url) else { return }
            LibraryStore.shared.nameBookmark(id, host: host, title: title)
        }
    }
}
