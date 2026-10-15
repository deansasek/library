import Foundation

/// Reads and writes library backup files. Pure: it takes bytes and returns items or throws, so it can be checked
/// without a window. A backup holds the library tree and nothing else. Clipboard data is never included, because
/// pinned clipboard items are encrypted with a key that stays on this Mac.
enum LibraryBackup {
    static let format = "library-backup"
    static let version = 1

    /// The versioned file. `version` is checked before `items` is read, so a newer file is refused cleanly.
    private struct Envelope: Codable {
        let format: String
        let version: Int
        let exportedAt: Date
        let items: [LibraryItem]
    }

    /// Only the fields that decide what kind of file this is. Read first, so the error can say what is wrong.
    private struct Header: Decodable {
        let format: String?
        let version: Int?
    }

    enum BackupError: Error, Equatable {
        /// The data is not JSON, or it is truncated, or its items do not decode.
        case malformed
        /// The file is JSON but is not a Library backup.
        case wrongFormat
        /// The file is a Library backup from a version this app does not read.
        case unsupportedVersion(Int)
        /// Two items share an id, so the tree cannot be restored as it was saved.
        case duplicateIDs

        var message: String {
            switch self {
            case .malformed:
                "The file is damaged or incomplete."
            case .wrongFormat:
                "The file isn’t a Library backup."
            case .unsupportedVersion(let found):
                "The backup uses format version \(found). This version of Library reads version \(LibraryBackup.version). Update Library to restore it."
            case .duplicateIDs:
                "Two items in the backup have the same identifier."
            }
        }
    }

    /// Encodes the library as a versioned backup. Pretty-printed with sorted keys, so the file diffs cleanly.
    static func encode(_ items: [LibraryItem], exportedAt: Date = Date()) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Envelope(format: format, version: version, exportedAt: exportedAt, items: items))
    }

    /// Decodes a versioned backup, or a bare bookmarks.json array from before backups existed.
    static func decode(_ data: Data) -> Result<[LibraryItem], BackupError> {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let header = try? decoder.decode(Header.self, from: data) else {
            // A bare array has no header. It is accepted only if its items decode.
            guard let items = try? decoder.decode([LibraryItem].self, from: data) else {
                return .failure(.malformed)
            }
            return unique(withoutLoginCommands(items))
        }
        guard header.format == format else { return .failure(.wrongFormat) }
        guard let found = header.version, found == version else {
            return .failure(.unsupportedVersion(header.version ?? 0))
        }
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else {
            return .failure(.malformed)
        }
        return unique(withoutLoginCommands(envelope.items))
    }

    /// A file someone else sent can mark a terminal command to run at login. The mark is removed on read, so it runs at
    /// login only if you turn it on again in Get Info.
    static func withoutLoginCommands(_ items: [LibraryItem]) -> [LibraryItem] {
        items.map { item in
            var copy = item
            if copy.command != nil { copy.openAtLogin = nil }
            if let children = copy.children { copy.children = withoutLoginCommands(children) }
            return copy
        }
    }

    /// Rejects trees with repeated ids. Ids name items everywhere in the app, so a repeat would make edits hit the wrong item.
    private static func unique(_ items: [LibraryItem]) -> Result<[LibraryItem], BackupError> {
        let ids = items.allIDs
        return Set(ids).count == ids.count ? .success(items) : .failure(.duplicateIDs)
    }

    /// What a restore puts in the live library. A bookmarks.json copy also holds Recently Deleted items, which stay
    /// deleted. An item whose id is already used in Recently Deleted gets a new id, children included, since Restore,
    /// Delete Immediately, and sync look items up by id and one id must name one item.
    static func restorable(_ items: [LibraryItem], avoiding deleted: [LibraryItem]) -> [LibraryItem] {
        replacingIDs(items.filter { $0.deletedDate == nil }, taken: Set(deleted.allIDs))
    }

    private static func replacingIDs(_ items: [LibraryItem], taken: Set<UUID>) -> [LibraryItem] {
        items.map { item in
            var item = item
            if taken.contains(item.id) { item.id = UUID() }
            if let children = item.children { item.children = replacingIDs(children, taken: taken) }
            return item
        }
    }
}
