import Foundation

/// Reads bookmarks from a Safari `Bookmarks.plist` or from a Chromium `Bookmarks` JSON file (Chrome, Edge, Brave,
/// Chromium, and others). Pure: it takes bytes and returns a folder of library items or throws. Malformed input
/// throws and never crashes.
enum BookmarkImport {
    enum Browser: String {
        case safari = "Safari"
        case chrome = "Chrome"
    }

    struct Result {
        let browser: Browser
        /// "Imported from Safari" or "Imported from Chrome". Its children mirror the browser's folders.
        let folder: LibraryItem
        /// Bookmarks added to the folder.
        let imported: Int
        /// Bookmark entries left out because the address is not a web (http or https) link.
        let skipped: Int
    }

    enum Failure: Error, Equatable {
        /// The data is not a Safari or Chromium bookmarks file.
        case notBookmarks
        /// The bookmarks nest deeper than any real browser allows, so the file is treated as damaged.
        case tooDeep
    }

    /// Deeper nesting than this is treated as damage. It keeps the recursion bounded.
    private static let maxDepth = 64

    /// Safari keeps its Reading List and Sync data in folders with `com.apple.` titles. They are not bookmarks.
    private static let skippedSafariPrefix = "com.apple."

    private struct Tally {
        var imported = 0
        var skipped = 0
    }

    static func parse(_ data: Data) throws -> Result {
        if let result = try parseSafari(data) { return result }
        if let result = try parseChromium(data) { return result }
        throw Failure.notBookmarks
    }

    // MARK: Safari

    /// Returns nil when the data is not a Safari bookmarks property list.
    private static func parseSafari(_ data: Data) throws -> Result? {
        guard let root = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              root["WebBookmarkType"] as? String == "WebBookmarkTypeList" else { return nil }
        var tally = Tally()
        let items = try safariNodes(root["Children"] as? [Any] ?? [], depth: 1, tally: &tally)
        return Result(
            browser: .safari,
            folder: LibraryItem(name: "Imported from Safari", children: items),
            imported: tally.imported,
            skipped: tally.skipped
        )
    }

    private static func safariNodes(_ nodes: [Any], depth: Int, tally: inout Tally) throws -> [LibraryItem] {
        guard depth <= maxDepth else { throw Failure.tooDeep }
        var items: [LibraryItem] = []
        for case let node as [String: Any] in nodes {
            switch node["WebBookmarkType"] as? String {
            case "WebBookmarkTypeLeaf":
                let url = node["URLString"] as? String ?? ""
                let title = (node["URIDictionary"] as? [String: Any])?["title"] as? String
                if let item = bookmark(title: title, url: url) {
                    items.append(item)
                    tally.imported += 1
                } else {
                    tally.skipped += 1
                }
            case "WebBookmarkTypeList":
                let title = node["Title"] as? String ?? ""
                guard !title.hasPrefix(skippedSafariPrefix) else { continue }
                let children = try safariNodes(node["Children"] as? [Any] ?? [], depth: depth + 1, tally: &tally)
                if !children.isEmpty {
                    items.append(LibraryItem(name: safariFolderName(title), children: children))
                }
            default:
                // Proxies and anything unknown are not bookmarks.
                continue
            }
        }
        return items
    }

    /// Safari's two top-level folders get the names Safari shows. Other folders keep their titles.
    private static func safariFolderName(_ title: String) -> String {
        switch title {
        case "BookmarksBar": return "Favorites Bar"
        case "BookmarksMenu": return "Bookmarks Menu"
        case "": return "Folder"
        default: return title
        }
    }

    // MARK: Chromium

    /// Returns nil when the data is not a Chromium bookmarks JSON file.
    private static func parseChromium(_ data: Data) throws -> Result? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let roots = root["roots"] as? [String: Any] else { return nil }
        var tally = Tally()
        var items: [LibraryItem] = []
        // The bookmark bar, the other bookmarks, and the mobile bookmarks, in Chrome's own order.
        for key in ["bookmark_bar", "other", "synced"] {
            guard let node = roots[key] as? [String: Any], node["type"] as? String == "folder" else { continue }
            let children = try chromiumNodes(node["children"] as? [Any] ?? [], depth: 1, tally: &tally)
            if !children.isEmpty {
                let name = (node["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? key
                items.append(LibraryItem(name: name, children: children))
            }
        }
        return Result(
            browser: .chrome,
            folder: LibraryItem(name: "Imported from Chrome", children: items),
            imported: tally.imported,
            skipped: tally.skipped
        )
    }

    private static func chromiumNodes(_ nodes: [Any], depth: Int, tally: inout Tally) throws -> [LibraryItem] {
        guard depth <= maxDepth else { throw Failure.tooDeep }
        var items: [LibraryItem] = []
        for case let node as [String: Any] in nodes {
            switch node["type"] as? String {
            case "url":
                if let item = bookmark(title: node["name"] as? String, url: node["url"] as? String ?? "") {
                    items.append(item)
                    tally.imported += 1
                } else {
                    tally.skipped += 1
                }
            case "folder":
                let children = try chromiumNodes(node["children"] as? [Any] ?? [], depth: depth + 1, tally: &tally)
                if !children.isEmpty {
                    let name = node["name"] as? String ?? ""
                    items.append(LibraryItem(name: name.isEmpty ? "Folder" : name, children: children))
                }
            default:
                continue
            }
        }
        return items
    }

    // MARK: Shared

    /// A bookmark for a web link, or nil for anything else (file, javascript, chrome settings, and so on).
    /// A bookmark without a title takes its host name.
    private static func bookmark(title: String?, url: String) -> LibraryItem? {
        let address = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: address),
              let scheme = parsed.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = parsed.host, !host.isEmpty else { return nil }
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return LibraryItem(name: name.isEmpty ? host : name, url: address)
    }
}
