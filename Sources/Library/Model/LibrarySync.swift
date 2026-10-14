import Foundation

/// Keeps bookmarks.json in iCloud Drive, behind the Settings toggle. The rules and the file steps are here, apart
/// from `LibraryStore`, so Tests/Checks can run them on temporary folders and never touch the real iCloud Drive.
///
/// Stamps: a change made on this Mac sets `modified` on each item it changed (`stamped`).
///
/// Merge: when the file changed on disk since Library last read or wrote it, `merge` combines the two copies.
///   1. The side whose newest change is later decides the tree: its order, its folders, and which items exist.
///   2. An item on both sides takes the copy with the later `modified`. A tie keeps the file's copy.
///   3. An item that only the other side has is kept, at the top level, when it is new since the last sync
///      (it was not known then) or changed after the deciding side's newest change. Otherwise the deciding side
///      deleted it.
/// Limits: a folder deleted on one Mac leaves its newer items at the top level. A delete can come back once when
/// the other Mac saved a later edit before it saw the delete.
enum LibrarySync {
    /// What the user picked when both sides have a library.
    enum Choice: Equatable {
        case useICloud, useThisMac, cancel
    }

    enum Prompt: Equatable {
        /// iCloud Drive is off, so there is no folder for the library.
        case unavailable
        /// iCloud has no library yet, so this Mac's library moves there.
        case move
        /// iCloud already has a library, so the user chooses which one stays.
        case askWhichToKeep
    }

    /// The decision for turning the option on.
    static func enablePrompt(iCloudFolderExists: Bool, cloudFileExists: Bool) -> Prompt {
        guard iCloudFolderExists else { return .unavailable }
        return cloudFileExists ? .askWhichToKeep : .move
    }

    /// One file operation. `run` performs them in order and stops at the first failure.
    enum Step: Equatable {
        case copy(from: URL, to: URL)
        case verify(URL, matches: URL)
        case remove(URL)
        case link(URL, to: URL)
    }

    enum SyncError: Error {
        case mismatch
    }

    /// Steps to turn the option on. `local` is ~/.library/bookmarks.json and `cloud` is the iCloud copy. The copy
    /// that is not kept goes to a backup in ~/.library first, so no library is lost.
    static func enableSteps(local: URL, cloud: URL, backupLocal: URL, backupCloud: URL,
                            prompt: Prompt, choice: Choice) -> [Step] {
        switch (prompt, choice) {
        case (_, .cancel), (.unavailable, _):
            return []
        case (.move, _), (.askWhichToKeep, .useThisMac):
            var steps: [Step] = []
            if prompt == .askWhichToKeep {
                steps.append(.copy(from: cloud, to: backupCloud))
            }
            return steps + [.copy(from: local, to: cloud), .verify(cloud, matches: local),
                            .remove(local), .link(local, to: cloud)]
        case (.askWhichToKeep, .useICloud):
            return [.copy(from: local, to: backupLocal), .remove(local), .link(local, to: cloud)]
        }
    }

    /// Steps to turn the option off. The link becomes a real file, which is checked against the iCloud copy before
    /// the iCloud copy is removed.
    static func disableSteps(local: URL, cloud: URL) -> [Step] {
        [.remove(local), .copy(from: cloud, to: local), .verify(local, matches: cloud), .remove(cloud)]
    }

    static func run(_ steps: [Step]) throws {
        let fm = FileManager.default
        for step in steps {
            switch step {
            case let .copy(from, to):
                try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(contentsOf: from).write(to: to, options: .atomic)
            case let .verify(file, other):
                guard let a = try? Data(contentsOf: file), let b = try? Data(contentsOf: other), a == b else {
                    throw SyncError.mismatch
                }
            case let .remove(url):
                try fm.removeItem(at: url)
            case let .link(at, to):
                try fm.createSymbolicLink(at: at, withDestinationURL: to)
            }
        }
    }

    /// After a failed `run`: when the library file is missing or is a link, copies the iCloud copy back to this Mac.
    /// A real file at `local` is never touched.
    static func recover(local: URL, cloud: URL) {
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: cloud) else { return }
        if linkDestination(of: local) != nil { try? fm.removeItem(at: local) }
        if !fm.fileExists(atPath: local.path) { try? data.write(to: local, options: .atomic) }
    }

    /// The iCloud Drive folder as the user sees it in Finder.
    static var iCloudFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }

    /// The library inside iCloud Drive, in a folder named Library.
    static func cloudFile(in iCloud: URL) -> URL {
        iCloud.appendingPathComponent("Library/bookmarks.json")
    }

    /// Where a symbolic link points, or nil when `link` is not a link. A relative target is taken from the link's folder.
    static func linkDestination(of link: URL) -> URL? {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { return nil }
        return target.hasPrefix("/")
            ? URL(fileURLWithPath: target)
            : link.deletingLastPathComponent().appendingPathComponent(target)
    }

    static func isLinked(_ link: URL) -> Bool {
        linkDestination(of: link) != nil
    }

    /// A link whose target is gone, for example because another Mac turned the option off and removed the iCloud copy.
    static func isDanglingLink(_ link: URL) -> Bool {
        guard let target = linkDestination(of: link) else { return false }
        return !FileManager.default.fileExists(atPath: target.path)
    }

    /// The placeholder iCloud leaves for a library whose contents are not on this Mac yet.
    static func isEvicted(_ cloud: URL) -> Bool {
        let placeholder = cloud.deletingLastPathComponent().appendingPathComponent(".bookmarks.json.icloud")
        return FileManager.default.fileExists(atPath: placeholder.path)
    }

    // MARK: - Stamps

    private struct Place: Equatable {
        let parent: UUID?
        let index: Int
    }

    /// `new` with `modified` set to `now` on each item that changed since `old`. An item changed when its fields
    /// or its place (folder and position) differs from `old`, or when it is new. The children and the stamp are
    /// not part of the fields, so a change inside a folder stamps only the item that changed.
    static func stamped(_ new: [LibraryItem], against old: [LibraryItem], at now: Date) -> [LibraryItem] {
        var before: [UUID: (content: LibraryItem, place: Place)] = [:]
        func index(_ list: [LibraryItem], parent: UUID?) {
            for (position, item) in list.enumerated() {
                before[item.id] = (content(item), Place(parent: parent, index: position))
                if let children = item.children { index(children, parent: item.id) }
            }
        }
        index(old, parent: nil)
        func walk(_ list: [LibraryItem], parent: UUID?) -> [LibraryItem] {
            list.enumerated().map { position, item in
                var out = item
                let place = Place(parent: parent, index: position)
                let unchanged = before[item.id].map { $0.content == content(item) && $0.place == place } ?? false
                if !unchanged { out.modified = now }
                out.children = item.children.map { walk($0, parent: item.id) }
                return out
            }
        }
        return walk(new, parent: nil)
    }

    /// The fields an edit changes: the item without its children and its stamp. A folder stays a folder.
    private static func content(_ item: LibraryItem) -> LibraryItem {
        var copy = item
        copy.children = item.children == nil ? nil : []
        copy.modified = nil
        return copy
    }

    // MARK: - Merge

    struct Merge: Equatable {
        /// The merged library, in the deciding side's order.
        let items: [LibraryItem]
        /// Names of items where a change from the other Mac replaced an edit made here since the last sync.
        let replacedEdits: [String]
    }

    /// Merges `local` (this Mac's library, with unsaved edits) with `remote` (the file). `lastSynced` is when the file
    /// was last read or written, and `knownIDs` holds the ids the file had then. Both come from the store.
    static func merge(local: [LibraryItem], remote: [LibraryItem], lastSynced: Date, knownIDs: Set<UUID>) -> Merge {
        let localFlat = flat(local), remoteFlat = flat(remote)
        let localByID = byID(localFlat), remoteByID = byID(remoteFlat)
        let localNewest = newest(localFlat), remoteNewest = newest(remoteFlat)
        let remoteDecides = remoteNewest >= localNewest
        let otherFlat = remoteDecides ? localFlat : remoteFlat
        let decidingByID = remoteDecides ? remoteByID : localByID
        let decidingNewest = max(localNewest, remoteNewest)
        let deciding = remoteDecides ? remote : local
        var notices: [String] = []

        func rebuild(_ list: [LibraryItem]) -> [LibraryItem] {
            list.map { node in
                var out = node
                if let mine = localByID[node.id], let theirs = remoteByID[node.id] {
                    let remoteWins = modified(theirs) >= modified(mine)
                    if remoteWins, modified(mine) > lastSynced, content(mine) != content(theirs) {
                        notices.append(mine.name)
                    }
                    out = remoteWins ? theirs : mine
                }
                out.children = node.children.map(rebuild)
                return out
            }
        }
        var items = rebuild(deciding)

        // Items only on the other side. Ones this Mac has never seen are kept, and so are ones changed after the
        // deciding side's newest change. The rest were deleted on the deciding side.
        let added = otherFlat.filter { item in
            decidingByID[item.id] == nil
                && (!knownIDs.contains(item.id) || modified(item) > decidingNewest)
        }
        items += added.map { item in
            var copy = item
            copy.children = item.children == nil ? nil : []
            return copy
        }
        return Merge(items: items, replacedEdits: notices)
    }

    private static func modified(_ item: LibraryItem) -> Date {
        item.modified ?? .distantPast
    }

    private static func newest(_ items: [LibraryItem]) -> Date {
        items.map(modified).max() ?? .distantPast
    }

    private static func flat(_ list: [LibraryItem]) -> [LibraryItem] {
        list.flatMap { [$0] + flat($0.children ?? []) }
    }

    private static func byID(_ items: [LibraryItem]) -> [UUID: LibraryItem] {
        Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
