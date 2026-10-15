import Foundation

/// The table read from the start of a CSV or TSV file. `truncated` is true when the file has more rows or bytes
/// than were read, so the table shows only its beginning.
struct DelimitedTable: Equatable {
    var headers: [String]
    var rows: [[String]]
    var truncated: Bool
}

/// Splits CSV or TSV text into records and fields. It is a pure function, so the checks can test it without a file.
/// Quoted fields may hold the delimiter and line breaks. A doubled quote inside a quoted field is one quote. CRLF,
/// LF, and CR each end a record. Blank lines are skipped. The first record is the header.
enum DelimitedParser {
    /// The most data rows shown, not counting the header.
    static let defaultMaxRows = 500

    /// Parses `text`. Stops after `maxRows` data rows and marks the table truncated when more follow.
    /// `inputIsPartial` says the text was cut from a longer file. Its last record may be incomplete, so that record
    /// is dropped and the table is marked truncated.
    static func parse(_ text: String, delimiter: Unicode.Scalar = ",", maxRows: Int = defaultMaxRows,
                      inputIsPartial: Bool = false) -> DelimitedTable {
        var scalars = Array(text.unicodeScalars)
        // A byte order mark at the start of a file is not part of the first header.
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }

        var records = Records(limit: maxRows + 1)
        var record: [String] = []
        var field = ""
        var inQuotes = false
        // True once anything has been read for the current record, so a last line without a line break still counts.
        var pending = false
        var i = 0
        let n = scalars.count

        scan: while i < n {
            let c = scalars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < n && scalars[i + 1] == "\"" {
                        field.unicodeScalars.append("\"")
                        i += 2
                    } else {
                        inQuotes = false
                        i += 1
                    }
                } else {
                    field.unicodeScalars.append(c)
                    i += 1
                }
                continue
            }
            if c == "\"" && field.isEmpty {
                // A quote opens a quoted field only at its start. Elsewhere it is an ordinary character.
                inQuotes = true
                pending = true
                i += 1
            } else if c == delimiter {
                record.append(field)
                field = ""
                pending = true
                i += 1
            } else if c == "\r" || c == "\n" {
                // CRLF is one line break.
                i += (c == "\r" && i + 1 < n && scalars[i + 1] == "\n") ? 2 : 1
                record.append(field)
                field = ""
                if !records.add(record) { break scan }
                record = []
                pending = false
            } else {
                field.unicodeScalars.append(c)
                pending = true
                i += 1
            }
        }

        if !records.overflow && pending && !inputIsPartial {
            record.append(field)
            _ = records.add(record)
        }
        let rows = records.rows
        return DelimitedTable(headers: rows.first ?? [], rows: Array(rows.dropFirst()),
                              truncated: records.overflow || inputIsPartial)
    }

    /// The records kept so far. A record with one empty field is a blank line and is skipped.
    private struct Records {
        let limit: Int
        var rows: [[String]] = []
        var overflow = false

        init(limit: Int) { self.limit = limit }

        /// Keeps the record. Returns false when it does not fit, which ends the parse.
        mutating func add(_ record: [String]) -> Bool {
            if record == [""] { return true }
            if rows.count == limit {
                overflow = true
                return false
            }
            rows.append(record)
            return true
        }
    }
}

/// What the preview may do with a file. Only regular files are read, and a symbolic link is never followed: a file
/// reached through one is refused, so a preview cannot show a file outside the folder it was chosen in.
enum FilePreviewAccess {
    enum Verdict: Equatable {
        case regular(size: Int64)
        case symlink
        case notRegular
        case missing
    }

    /// Checks each part of the path with lstat, so a link anywhere along the way is seen, not only the last part.
    /// The system's own top-level aliases (/var, /tmp, /etc, which point into /private) are allowed. Any other link
    /// is refused.
    static func check(_ url: URL) -> Verdict {
        let parts = url.standardizedFileURL.pathComponents.filter { $0 != "/" }
        guard !parts.isEmpty else { return .notRegular }
        var path = ""
        for (index, part) in parts.enumerated() {
            path += "/" + part
            var info = stat()
            guard lstat(path, &info) == 0 else { return .missing }
            let type = info.st_mode & S_IFMT
            if type == S_IFLNK {
                let isSystemAlias = index < 1 && resolved(path) == "/private" + path
                if !isSystemAlias { return .symlink }
            }
            if index == parts.count - 1 {
                return type == S_IFREG ? .regular(size: Int64(info.st_size)) : .notRegular
            }
            if type != S_IFDIR && type != S_IFLNK { return .notRegular }
        }
        return .notRegular
    }

    private static func resolved(_ path: String) -> String? {
        guard let real = realpath(path, nil) else { return nil }
        defer { free(real) }
        return String(cString: real)
    }
}

/// How Quick Open previews a file: a table for delimited text, and Quick Look for everything else.
enum FilePreviewKind: Equatable {
    case quickLook
    case table(delimiter: Unicode.Scalar)

    init(_ url: URL) {
        switch url.pathExtension.lowercased() {
        case "csv": self = .table(delimiter: ",")
        case "tsv": self = .table(delimiter: "\t")
        default: self = .quickLook
        }
    }
}

/// The result of loading a file for the preview pane.
enum FilePreviewState: Equatable {
    case loading
    case quickLook(URL)
    case table(DelimitedTable)
    case tooLarge
    case unavailable
}

enum FilePreviewLoader {
    /// Table files larger than this are refused, so a big file never holds up the panel.
    static let maxTableBytes: Int64 = 25 * 1024 * 1024
    /// The most bytes read from a table file. The parser sees only these.
    static let readLimit = 64 * 1024
    /// Table columns shown. A wider table is cut here, and the view says so.
    static let maxShownColumns = 40

    /// Loads a file off the main actor. Cancelling the caller's task cancels the read.
    static func load(_ url: URL) async -> FilePreviewState {
        let work = Task.detached(priority: .userInitiated) { () -> FilePreviewState in
            do {
                return try state(for: url)
            } catch {
                return .unavailable
            }
        }
        return await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
    }

    /// The blocking part of `load`. It checks the file, then reads at most `readLimit` bytes of a table file.
    static func state(for url: URL) throws -> FilePreviewState {
        let kind = FilePreviewKind(url)
        switch FilePreviewAccess.check(url) {
        case .regular(let size):
            switch kind {
            case .quickLook:
                return .quickLook(url)
            case .table(let delimiter):
                if size > maxTableBytes { return .tooLarge }
                try Task.checkCancellation()
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: readLimit) ?? Data()
                try Task.checkCancellation()
                // A cut in the middle of a character becomes a replacement character, and that record is dropped.
                let text = String(decoding: data, as: UTF8.self)
                return .table(DelimitedParser.parse(text, delimiter: delimiter, inputIsPartial: size > readLimit))
            }
        case .symlink, .notRegular, .missing:
            return .unavailable
        }
    }
}
