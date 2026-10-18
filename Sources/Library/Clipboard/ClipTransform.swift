import Foundation

/// The ways Copy as… rewrites a text clip. Each is a pure function of the text, so the copy can be tested without a
/// pasteboard. The result is copied as a new clipboard entry, and the clip stays in the history as it was.
enum ClipTransform: CaseIterable {
    case plainText, trimmed, lowercase, uppercase, joinedLines, smartPunctuation

    /// The name in the Copy as… menu.
    var title: String {
        switch self {
        case .plainText: return String(localized: "Plain Text", bundle: L10n.bundle)
        case .trimmed: return String(localized: "Trimmed Whitespace", bundle: L10n.bundle)
        case .lowercase: return String(localized: "Lowercase", bundle: L10n.bundle)
        case .uppercase: return String(localized: "Uppercase", bundle: L10n.bundle)
        case .joinedLines: return String(localized: "Joined Lines", bundle: L10n.bundle)
        case .smartPunctuation: return String(localized: "Smart Punctuation", bundle: L10n.bundle)
        }
    }

    func apply(_ text: String) -> String {
        switch self {
        case .plainText:
            return text
        case .trimmed:
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .lowercase:
            return text.lowercased()
        case .uppercase:
            return text.uppercased()
        case .joinedLines:
            // Each line break, including a CRLF pair, becomes one space. Character.isNewline counts CRLF as one break.
            // Empty pieces are dropped, so a break at the end adds nothing and a run of breaks (a blank line) adds one
            // space rather than one per break.
            return text.split(whereSeparator: \.isNewline).joined(separator: " ")
        case .smartPunctuation:
            return Self.smartPunctuation(text)
        }
    }

    /// Straight quotes become curly quotes, an apostrophe becomes ’, "--" becomes an em dash, and "..." becomes an
    /// ellipsis. A quote opens when nothing or a space, bracket, or dash comes before it. Other text is left alone.
    static func smartPunctuation(_ text: String) -> String {
        let chars = Array(text)
        var out = ""
        out.reserveCapacity(text.utf8.count)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            let before: Character? = i > 0 ? chars[i - 1] : nil
            let after: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if c == "-", after == "-" {
                out.append("—")
                i += 2
                continue
            }
            if c == ".", after == ".", i + 2 < chars.count, chars[i + 2] == "." {
                out.append("…")
                i += 3
                continue
            }
            switch c {
            case "\"":
                out.append(opens(after: before) ? "“" : "”")
            case "'":
                // A digit after an opening position is an abbreviated year, as in ’90s.
                let openingQuote = opens(after: before) && after?.isNumber != true
                out.append(openingQuote ? "‘" : "’")
            default:
                out.append(c)
            }
            i += 1
        }
        return out
    }

    /// True when a quote that follows `previous` opens a quotation rather than closing one.
    private static func opens(after previous: Character?) -> Bool {
        guard let previous else { return true }
        return previous.isWhitespace || "([{<\"'“‘—–-".contains(previous)
    }
}
