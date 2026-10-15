import AppKit

/// A bookmark or copied link as a Markdown link, [Title](url). The plain text is the Markdown. The rich text is the
/// title as a link, so a rich text field gets a real link.
enum MarkdownLink {
    /// The characters that have a meaning in Markdown. In a title, each is escaped with a backslash.
    private static let specialCharacters: Set<Character> = ["[", "]", "\\", "*", "_", "`"]

    /// The title with each Markdown special character escaped.
    static func escapedTitle(_ title: String) -> String {
        var result = ""
        for character in title {
            if specialCharacters.contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }

    /// The URL as a Markdown link destination. Spaces, parentheses, angle brackets, and backslashes are percent-encoded,
    /// so none of them can end the link early or escape its closing parenthesis.
    static func destination(_ url: String) -> String {
        url.replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
            .replacingOccurrences(of: "<", with: "%3C")
            .replacingOccurrences(of: ">", with: "%3E")
            .replacingOccurrences(of: "\\", with: "%5C")
    }

    /// The title to show: the trimmed title with each run of white space, including line breaks, shortened to one space,
    /// or the URL when the title is blank. A line break would end a Markdown link early, so none is kept.
    static func displayTitle(_ title: String, url: String) -> String {
        let words = title.split(whereSeparator: \.isWhitespace)
        return words.isEmpty ? url : words.joined(separator: " ")
    }

    /// The Markdown link for a title and URL, as typed in Markdown.
    static func markdown(title: String, url: String) -> String {
        "[\(escapedTitle(displayTitle(title, url: url)))](\(destination(url)))"
    }

    /// The title as a link in rich text. Nil when there is no title or the URL is not valid.
    static func richText(title: String, url: String) -> Data? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let link = URL(string: url) else { return nil }
        let text = NSAttributedString(string: trimmed, attributes: [.link: link])
        return text.rtf(from: NSRange(location: 0, length: text.length), documentAttributes: [:])
    }

    /// Puts the link on the pasteboard: the Markdown as plain text, and the rich text link when there is a title.
    static func copy(title: String, url: String, to pasteboard: NSPasteboard) {
        let item = NSPasteboardItem()
        item.setString(markdown(title: title, url: url), forType: .string)
        if let rtf = richText(title: title, url: url) {
            item.setData(rtf, forType: .rtf)
        }
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }
}
