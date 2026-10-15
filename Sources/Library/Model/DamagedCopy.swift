import Foundation

/// Keeps a damaged file for inspection. Each copy gets a timestamped name that is never used before, so a second
/// damage event adds a copy and leaves the first one alone. Nothing is ever replaced.
enum DamagedCopy {
    /// The name for attempt `attempt` (0 is the first try). Sorts by time, for example
    /// `bookmarks-damaged-2026-10-15T224917.123.json`. Later attempts add `-2`, `-3`, and so on.
    static func fileName(stem: String, ext: String, at date: Date, attempt: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HHmmss.SSS"
        let suffix = attempt == 0 ? "" : "-\(attempt + 1)"
        return "\(stem)-\(formatter.string(from: date))\(suffix).\(ext)"
    }

    /// Copies `file` next to itself under a new name, or moves it when `moving` is true. Returns the new file, or nil
    /// when no copy could be written. A name that is already taken is skipped, never overwritten.
    static func preserve(_ file: URL, stem: String, ext: String, moving: Bool, at date: Date = Date()) -> URL? {
        let folder = file.deletingLastPathComponent()
        for attempt in 0..<1000 {
            let target = folder.appendingPathComponent(fileName(stem: stem, ext: ext, at: date, attempt: attempt))
            if FileManager.default.fileExists(atPath: target.path) { continue }
            do {
                if moving {
                    try FileManager.default.moveItem(at: file, to: target)
                } else {
                    try FileManager.default.copyItem(at: file, to: target)
                }
                return target
            } catch {
                // Another write may have taken the name after the check above. Any other failure is final.
                if FileManager.default.fileExists(atPath: target.path) { continue }
                NSLog("Library: could not keep a copy of \(file.lastPathComponent) as \(target.lastPathComponent): \(error)")
                return nil
            }
        }
        return nil
    }
}
