import Foundation

/// Where a bookmark stands in the Reading List. An item with no state is not in the list.
enum ReadLaterState: String, Codable {
    case unread, read
}

/// The Reading List: bookmarks marked to read later. Unread items come before read ones.
enum ReadingList {
    /// What the user asks the list to do with an item.
    enum Action: Equatable {
        case add, markRead, markUnread, remove

        /// The menu title, and the name of the undo step.
        var title: String {
            switch self {
            case .add: return String(localized: "Add to Reading List", bundle: L10n.bundle)
            case .markRead: return String(localized: "Mark as Read", bundle: L10n.bundle)
            case .markUnread: return String(localized: "Mark as Unread", bundle: L10n.bundle)
            case .remove: return String(localized: "Remove from Reading List", bundle: L10n.bundle)
            }
        }
    }

    /// The state after `action`. Adding gives unread, and keeps a state the item already has. Marking changes only an
    /// item that is in the list, so it never adds one. Removing clears the state.
    static func state(after action: Action, from current: ReadLaterState?) -> ReadLaterState? {
        switch action {
        case .add: return current ?? .unread
        case .markRead: return current == nil ? nil : .read
        case .markUnread: return current == nil ? nil : .unread
        case .remove: return nil
        }
    }

    /// The items in the list, unread first, then read. Each group keeps the order the items came in.
    static func ordered(_ items: [LibraryItem]) -> [LibraryItem] {
        let listed = items.filter { $0.readLater != nil }
        return listed.filter { $0.readLater == .unread } + listed.filter { $0.readLater == .read }
    }
}
