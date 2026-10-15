import Foundation

/// Keeps bookmarks.json in iCloud Drive, behind the Settings toggle. The rules and the file steps are here, apart
/// from `LibraryStore`, so Tests/Checks can run them on temporary folders and never touch the real iCloud Drive.
///
/// Reads and writes of the iCloud copy go through NSFileCoordinator (`read`, `write`, `coordinated`). Conflicts are
/// not merged. iCloud Drive keeps the versions that were edited on two Macs at once (NSFileVersion), and the user
/// picks one (`resolve`), or picks each item that differs (`differences`, then `resolve` with the choices).
///
/// Deletes: an item deleted from the library moves to Recently Deleted as a tombstone (`deletedDate` set, its
/// subtree kept with it). Tombstones are removed for good after `retention`.
enum LibrarySync {
    // MARK: - Contents

    /// A library as the file holds it: the live items, and the items in Recently Deleted. Both are top-level lists;
    /// a deleted folder keeps its subtree. The file is `live` followed by `deleted`.
    struct Contents: Equatable {
        var live: [LibraryItem]
        var deleted: [LibraryItem]

        init(live: [LibraryItem] = [], deleted: [LibraryItem] = []) {
            self.live = live
            self.deleted = deleted
        }

        init(file items: [LibraryItem]) {
            live = items.filter { $0.deletedDate == nil }
            deleted = items.filter { $0.deletedDate != nil }
        }

        var file: [LibraryItem] { live + deleted }
    }

    /// How long a deleted item stays in Recently Deleted.
    static let retention: TimeInterval = 30 * 24 * 60 * 60

    /// Moves the items in `ids` to Recently Deleted. An item inside a selected folder goes with the folder.
    static func tombstone(_ ids: Set<UUID>, in contents: inout Contents, at date: Date) {
        for id in topmost(ids, in: contents.live) {
            let parent = parentID(of: id, in: contents.live)
            guard var node = contents.live.removeNode(id) else { continue }
            node.deletedDate = date
            node.deletedFrom = parent
            contents.deleted.append(node)
        }
    }

    /// Puts the deleted items in `ids` back. An item goes back into its folder when that folder is live, else to the top level.
    /// `ids` may name a deleted item's children; the whole deleted item is restored.
    static func restore(_ ids: Set<UUID>, in contents: inout Contents) {
        let matched = contents.deleted.filter { node in ids.contains { node.contains($0) } }
        contents.deleted.removeAll { node in ids.contains { node.contains($0) } }
        for var node in matched {
            let folder = node.deletedFrom
            node.deletedDate = nil
            node.deletedFrom = nil
            let live = folder.flatMap { id in contents.live.folders().contains { $0.id == id } ? id : nil }
            contents.live.append(node, to: live)
        }
    }

    /// Removes the deleted items in `ids`, with their subtrees, for good.
    static func deleteImmediately(_ ids: Set<UUID>, in contents: inout Contents) {
        contents.deleted.removeAll { node in ids.contains { node.contains($0) } }
    }

    /// Removes the deleted items older than `retention`.
    static func purge(_ contents: inout Contents, now: Date) {
        contents.deleted.removeAll { now.timeIntervalSince($0.deletedDate ?? now) > retention }
    }

    /// The ids in `ids` that have no selected ancestor, in display order.
    static func topmost(_ ids: Set<UUID>, in list: [LibraryItem]) -> [UUID] {
        var result: [UUID] = []
        func walk(_ nodes: [LibraryItem], covered: Bool) {
            for node in nodes {
                let selected = ids.contains(node.id)
                if selected && !covered { result.append(node.id) }
                walk(node.children ?? [], covered: covered || selected)
            }
        }
        walk(list, covered: false)
        return result
    }

    static func parentID(of id: UUID, in list: [LibraryItem]) -> UUID? {
        for node in list {
            if node.children?.contains(where: { $0.id == id }) == true { return node.id }
            if let found = parentID(of: id, in: node.children ?? []) { return found }
        }
        return nil
    }

    static func decode(_ data: Data) -> Contents? {
        (try? JSONDecoder().decode([LibraryItem].self, from: data)).map(Contents.init(file:))
    }

    static func encode(_ contents: Contents) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(contents.file)
    }

    // MARK: - Conflicts

    /// Which version an item takes when two versions differ.
    enum Side: Equatable {
        case thisMac, other
    }

    /// One item that differs between this Mac and the other version. `thisMac` and `other` describe each side.
    struct Difference: Equatable, Identifiable {
        let id: UUID
        let name: String
        let thisMac: String
        let other: String
    }

    private struct Record: Equatable {
        let item: LibraryItem
        let parent: UUID?
    }

    /// Every node in display order, with its parent. `item` has no children, but folders keep an empty list.
    private static func records(_ items: [LibraryItem], parent: UUID? = nil) -> [Record] {
        items.flatMap { node -> [Record] in
            var item = node
            item.children = node.children == nil ? nil : []
            return [Record(item: item, parent: parent)] + records(node.children ?? [], parent: node.id)
        }
    }

    /// The items that differ between the two versions: present on one side only, or changed in place or moved.
    static func differences(local: Contents, other: Contents) -> [Difference] {
        let localRecords = records(local.file), otherRecords = records(other.file)
        let localByID = Dictionary(localRecords.map { ($0.item.id, $0) }, uniquingKeysWith: { first, _ in first })
        let otherByID = Dictionary(otherRecords.map { ($0.item.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        var result: [Difference] = []
        for record in localRecords + otherRecords where seen.insert(record.item.id).inserted {
            let id = record.item.id
            let mine = localByID[id], theirs = otherByID[id]
            guard mine != theirs else { continue }
            result.append(Difference(id: id,
                                     name: (mine ?? theirs)?.item.name ?? "",
                                     thisMac: summary(mine),
                                     other: summary(theirs)))
        }
        return result
    }

    private static func summary(_ record: Record?) -> String {
        guard let record else { return "Not in this version" }
        if let date = record.item.deletedDate {
            return "Deleted \(date.formatted(date: .abbreviated, time: .omitted))"
        }
        if record.item.isFolder { return "Folder" }
        return record.item.url ?? record.item.command ?? record.item.appPath ?? "Item"
    }

    /// The library that results from choosing `preferring` for every item, except the items in `choices`.
    /// An item missing from the chosen side is removed. A child stays inside its folder, deleted or not, so a
    /// deleted folder takes its children with it. A child whose folder is gone goes to the top level.
    static func resolve(local: Contents, other: Contents, preferring: Side, choices: [UUID: Side]) -> Contents {
        let localRecords = records(local.file), otherRecords = records(other.file)
        let localByID = Dictionary(localRecords.map { ($0.item.id, $0) }, uniquingKeysWith: { first, _ in first })
        let otherByID = Dictionary(otherRecords.map { ($0.item.id, $0) }, uniquingKeysWith: { first, _ in first })
        let base = preferring == .thisMac ? localRecords : otherRecords
        let alternate = preferring == .thisMac ? otherRecords : localRecords
        var order: [UUID] = []
        var seen = Set<UUID>()
        for record in base + alternate where seen.insert(record.item.id).inserted {
            order.append(record.item.id)
        }
        var chosen: [UUID: Record] = [:]
        for id in order {
            let side = choices[id] ?? preferring
            if let record = side == .thisMac ? localByID[id] : otherByID[id] {
                chosen[id] = record
            }
        }
        // The parent a chosen item keeps, if any. Two folders that were each moved into the other, one on each Mac,
        // would both become children and neither would be shown, so an item whose parent chain leads back to itself
        // is shown at the top level instead.
        func keptParent(_ id: UUID) -> UUID? {
            guard let record = chosen[id], record.item.deletedDate == nil, let parent = record.parent, chosen[parent] != nil else {
                return nil
            }
            return parent
        }
        func inCycle(_ id: UUID) -> Bool {
            var current = keptParent(id)
            for _ in 0...chosen.count {
                guard let step = current else { return false }
                if step == id { return true }
                current = keptParent(step)
            }
            return false
        }
        var children: [UUID: [UUID]] = [:]
        var liveRoots: [UUID] = [], deletedRoots: [UUID] = []
        for id in order {
            guard let record = chosen[id] else { continue }
            if record.item.deletedDate != nil {
                deletedRoots.append(id)
            } else if let parent = keptParent(id), !inCycle(id) {
                children[parent, default: []].append(id)
            } else {
                liveRoots.append(id)
            }
        }
        func build(_ id: UUID) -> LibraryItem {
            var item = chosen[id]!.item
            if item.children != nil {
                item.children = (children[id] ?? []).map(build)
            }
            return item
        }
        return Contents(live: liveRoots.map(build), deleted: deletedRoots.map(build))
    }

    /// The name the system uses for the iCloud copy's unresolved conflict versions. Empty when there are none.
    static func unresolvedConflicts(at url: URL) -> [NSFileVersion] {
        NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
    }

    /// Marks the conflict versions resolved and removes the rest, after the user has chosen and the choice is saved.
    /// Copies every conflict version to `folder` before any of them is removed. Two or more diverged copies can hold
    /// edits the chosen version does not include, so none is deleted without a copy kept on this Mac.
    static func preserve(_ versions: [NSFileVersion], in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        for (index, version) in versions.enumerated() {
            let copy = folder.appendingPathComponent("bookmarks-\(stamp)-\(index).json")
            try FileManager.default.copyItem(at: version.url, to: copy)
        }
    }

    static func resolveConflicts(_ versions: [NSFileVersion], at url: URL) throws {
        for version in versions { version.isResolved = true }
        try NSFileVersion.removeOtherVersionsOfItem(at: url)
    }

    // MARK: - Sync status

    /// What the manager footer shows for the iCloud copy.
    enum SyncState: Equatable {
        case upToDate, waiting, uploading

        var label: String {
            switch self {
            case .upToDate: String(localized: "Up to date", bundle: L10n.bundle)
            case .waiting: String(localized: "Waiting for iCloud…", bundle: L10n.bundle)
            case .uploading: String(localized: "Uploading…", bundle: L10n.bundle)
            }
        }
    }

    /// Uploading wins over waiting: a file that is still being sent is shown as uploading.
    static func syncState(isUploading: Bool, isUploaded: Bool, downloading: URLUbiquitousItemDownloadingStatus?) -> SyncState {
        if isUploading || !isUploaded { return .uploading }
        if let downloading, downloading != .current { return .waiting }
        return .upToDate
    }

    /// The state of the iCloud copy, from its ubiquitous item keys. Nil when the file is not in iCloud Drive.
    static func syncState(of url: URL) -> SyncState? {
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemIsUploadingKey, .ubiquitousItemIsUploadedKey,
                                         .ubiquitousItemDownloadingStatusKey]
        guard let values = try? url.resourceValues(forKeys: keys), values.isUbiquitousItem == true else { return nil }
        return syncState(isUploading: values.ubiquitousItemIsUploading ?? false,
                         isUploaded: values.ubiquitousItemIsUploaded ?? true,
                         downloading: values.ubiquitousItemDownloadingStatus)
    }

    // MARK: - Enabling and disabling

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
        /// A file or link in ~/.library.
        case remove(URL)
        /// The iCloud copy, removed through NSFileCoordinator.
        case removeICloud(URL)
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
        [.remove(local), .copy(from: cloud, to: local), .verify(local, matches: cloud), .removeICloud(cloud)]
    }

    /// Performs the steps. Every read and write of a file goes through NSFileCoordinator. `presenter` is the
    /// library's file presenter, so its own writes do not come back to it as changes.
    static func run(_ steps: [Step], presenter: LibraryFilePresenter? = nil) throws {
        let fm = FileManager.default
        for step in steps {
            switch step {
            case let .copy(from, to):
                let data = try read(from, presenter: presenter)
                try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try write(data, to: to, presenter: presenter)
            case let .verify(file, other):
                guard let a = try? read(file, presenter: presenter), let b = try? read(other, presenter: presenter), a == b else {
                    throw SyncError.mismatch
                }
            case let .remove(url):
                try fm.removeItem(at: url)
            case let .removeICloud(url):
                try coordinated(url, .write(.forDeleting), presenter: presenter) { try fm.removeItem(at: $0) }
            case let .link(at, to):
                try fm.createSymbolicLink(at: at, withDestinationURL: to)
            }
        }
    }

    /// After a failed `run`: when the library file is missing or is a link, copies the iCloud copy back to this Mac.
    /// A real file at `local` is never touched.
    static func recover(local: URL, cloud: URL) {
        let fm = FileManager.default
        guard let data = try? read(cloud) else { return }
        if linkDestination(of: local) != nil { try? fm.removeItem(at: local) }
        if !fm.fileExists(atPath: local.path) { try? data.write(to: local, options: .atomic) }
    }

    // MARK: - Coordinated file access

    /// Reads a file through NSFileCoordinator.
    static func read(_ url: URL, presenter: LibraryFilePresenter? = nil) throws -> Data {
        try coordinated(url, .read, presenter: presenter) { try Data(contentsOf: $0) }
    }

    /// Replaces a file through NSFileCoordinator, atomically.
    static func write(_ data: Data, to url: URL, presenter: LibraryFilePresenter? = nil) throws {
        try coordinated(url, .write(.forReplacing), presenter: presenter) { try data.write(to: $0, options: .atomic) }
    }

    private enum Access {
        case read
        case write(NSFileCoordinator.WritingOptions)
    }

    /// Runs `body` on `url` while NSFileCoordinator holds it. Errors from the coordinator and from `body` are thrown.
    private static func coordinated<T>(_ url: URL, _ access: Access, presenter: LibraryFilePresenter?,
                                       _ body: (URL) throws -> T) throws -> T {
        var outcome: Result<T, Error>?
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator(filePresenter: presenter)
        switch access {
        case .read:
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { accessed in
                outcome = Result { try body(accessed) }
            }
        case let .write(options):
            coordinator.coordinate(writingItemAt: url, options: options, error: &coordinationError) { accessed in
                outcome = Result { try body(accessed) }
            }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw CocoaError(.fileWriteUnknown) }
        return try outcome.get()
    }

    // MARK: - Locations

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
}
