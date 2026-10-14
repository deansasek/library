import CryptoKit
import Foundation

/// The rules for keeping unpinned clipboard history across restarts. Everything here is pure, so the checks can test it
/// without the pasteboard, the Keychain, or the disk.
enum HistoryRestart {
    /// Images over this size are never saved, so the history file stays small. Other items keep the normal item limit.
    static let maxSavedImageBytes = 5_000_000

    /// Whether an item is written to the history file. Pinned items are not, because clipboard.json already keeps them.
    /// Items that were private or from a password manager were never recorded, so they cannot reach this.
    static func saves(kind: ClipItem.Kind, byteCount: Int, pinned: Bool, keeps: Bool) -> Bool {
        guard keeps, !pinned, byteCount <= ClipboardHistory.maxItemBytes else { return false }
        return kind != .image || byteCount <= maxSavedImageBytes
    }

    /// `current` with the restored items added. Each digest appears once, so a restored item that is already present,
    /// as a copy made during the load or as a pin, is skipped. Each new item goes where its copy time puts it, as a copy does.
    /// `current` is newest first, as the history keeps it.
    static func merge(_ current: [ClipItem], restored: [ClipItem]) -> [ClipItem] {
        var result = current
        for item in restored.sorted(by: { $0.date > $1.date }) where !result.contains(where: { $0.digest == item.digest }) {
            result.insert(item, at: result.firstIndex { $0.date < item.date } ?? result.count)
        }
        return result
    }

    /// Drops the oldest unpinned items until the count and total size fit. Pinned items are never dropped.
    static func limited(_ items: [ClipItem], maxItems: Int, maxTotalBytes: Int) -> [ClipItem] {
        var kept = items
        var unpinnedCount = kept.reduce(0) { $0 + ($1.pinned ? 0 : 1) }
        var total = kept.reduce(0) { $0 + $1.byteCount }
        while let oldest = kept.lastIndex(where: { !$0.pinned }), unpinnedCount > maxItems || total > maxTotalBytes {
            total -= kept[oldest].byteCount
            unpinnedCount -= 1
            kept.remove(at: oldest)
        }
        return kept
    }

    /// The newest of the restored items. It is the one copied at launch.
    static func latest(in restored: [ClipItem]) -> ClipItem? {
        restored.max { $0.date < $1.date }
    }

    /// Whether the newest restored item goes on the system clipboard at launch. It never does when something was copied
    /// since launch, so a fresh copy is not replaced.
    static func copiesLatestAtLaunch(keeps: Bool, restoresLatest: Bool, latest: ClipItem?, copiedSinceLaunch: Bool) -> Bool {
        keeps && restoresLatest && latest != nil && !copiedSinceLaunch
    }
}

/// The history file: the unpinned items as JSON, sealed with the Keychain key by PinnedFile. Unlike clipboard.json there
/// is no plain-text fallback, so text is never read or written unencrypted.
enum HistoryFile {
    enum Read {
        case clips([PinnedFile.Clip])
        /// Not sealed with the key. With no key, this also means the file cannot be checked.
        case unreadable
    }

    static func encode(_ clips: [PinnedFile.Clip], key: SymmetricKey) throws -> Data {
        try PinnedFile.seal(JSONEncoder().encode(clips), key: key)
    }

    static func read(_ data: Data, key: SymmetricKey?) -> Read {
        guard let key, let plain = try? PinnedFile.open(data, key: key),
              let clips = try? JSONDecoder().decode([PinnedFile.Clip].self, from: plain) else { return .unreadable }
        return .clips(clips)
    }
}
