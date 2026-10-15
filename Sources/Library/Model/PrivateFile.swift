import Foundation

/// Writes files that only their owner can read. Exports and snippets.json hold URLs, commands, and templates.
enum PrivateFile {
    static let mode = 0o600

    /// An atomic write creates the file with the default mode (0644), so the mode is set after the write.
    static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }

    static func isPrivate(_ url: URL) -> Bool {
        let value = try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
        return (value as? NSNumber)?.intValue == mode
    }
}
