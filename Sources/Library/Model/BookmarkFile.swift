import Foundation

/// Reads bookmarks.json. Kept apart from `LibraryStore` so each outcome can be checked on its own.
enum BookmarkFile {
    enum Load {
        /// No file yet, so Library starts with a default library.
        case missing
        /// The file exists but cannot be read, for example because of its permissions. Library leaves it alone.
        case unreadable
        /// The file reads but is not a library.
        case damaged
        case loaded([LibraryItem])
    }

    static func load(from file: URL) -> Load {
        guard FileManager.default.fileExists(atPath: file.path) else { return .missing }
        guard let data = try? Data(contentsOf: file) else { return .unreadable }
        guard let items = try? JSONDecoder().decode([LibraryItem].self, from: data) else { return .damaged }
        return .loaded(items)
    }
}
