import Foundation

/// The ways Copy as… rewrites a text clip. Each is a pure function of the text, so the copy can be tested without a
/// pasteboard. The result is copied as a new clipboard entry, and the clip stays in the history as it was.
enum ClipTransform: CaseIterable {
    case plainText, trimmed, lowercase, uppercase, joinedLines

    /// The name in the Copy as… menu.
    var title: String {
        switch self {
        case .plainText: return String(localized: "Plain Text", bundle: L10n.bundle)
        case .trimmed: return String(localized: "Trimmed Whitespace", bundle: L10n.bundle)
        case .lowercase: return String(localized: "Lowercase", bundle: L10n.bundle)
        case .uppercase: return String(localized: "Uppercase", bundle: L10n.bundle)
        case .joinedLines: return String(localized: "Joined Lines", bundle: L10n.bundle)
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
            return text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).joined(separator: " ")
        }
    }
}
