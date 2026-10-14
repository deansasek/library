import Foundation

/// Reads the `<title>` of a web page, for a bookmark named from its page. Only the first 64 KB of the page is read,
/// so a page whose title comes later is not named.
enum PageTitle {
    /// The most bytes of a page that are read for its title.
    static let readLimit = 64 * 1024
    /// The most seconds the whole request may take.
    static let timeout: TimeInterval = 5
    /// The most redirects followed.
    static let maxRedirects = 3

    /// The title of a page at `url`, or nil when the page cannot be read, is not a 200 response, or has no title.
    /// Nothing is kept: the request uses no cookies and no cache.
    static func fetch(_ url: URL) async -> String? {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let agent = "Library/\(version)"
        let options = WebFetch.Options(limit: readLimit, timeout: timeout, maxRedirects: maxRedirects,
                                       userAgent: agent, keepsPrefix: true)
        guard let (data, response) = await WebFetch.fetch(url, options: options), response.statusCode == 200 else {
            return nil
        }
        return title(in: data)
    }

    /// The title in the first 64 KB of a page's bytes, or nil.
    static func title(in data: Data) -> String? {
        let head = data.prefix(readLimit)
        // Decoding replaces a byte cut in the middle of a character, so the cut never fails the whole page.
        return extract(from: String(decoding: head, as: UTF8.self))
    }

    /// The text of the first `<title>` element in `html`, with entities decoded and whitespace collapsed. Nil when
    /// there is no title or it is empty. A title split over several lines is joined with single spaces.
    static func extract(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<title(?:\s[^>]*)?>(.*?)</title\s*>"#,
                                                   options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        let title = collapsingWhitespace(decodingEntities(String(html[range])))
        return title.isEmpty ? nil : title
    }

    /// Replaces each `&name;`, `&#123;`, or `&#x7B;` with its character, in one pass, so `&amp;lt;` becomes `&lt;`
    /// and not `<`. An unknown name or an invalid number is left as it is.
    static func decodingEntities(_ text: String) -> String {
        guard text.contains("&"), let regex = try? NSRegularExpression(pattern: #"&(#[xX][0-9A-Fa-f]{1,6}|#[0-9]{1,7}|[A-Za-z][A-Za-z0-9]{1,31});"#) else {
            return text
        }
        let nsText = text as NSString
        var result = ""
        var position = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            result += nsText.substring(with: NSRange(location: position, length: match.range.location - position))
            let name = nsText.substring(with: match.range(at: 1))
            result += decoded(name) ?? nsText.substring(with: match.range)
            position = match.range.location + match.range.length
        }
        result += nsText.substring(from: position)
        return result
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "ndash": "\u{2013}", "mdash": "\u{2014}", "hellip": "\u{2026}", "lsquo": "\u{2018}", "rsquo": "\u{2019}",
        "ldquo": "\u{201C}", "rdquo": "\u{201D}", "copy": "\u{00A9}", "reg": "\u{00AE}", "trade": "\u{2122}",
    ]

    /// The character for an entity's name (without `&` and `;`), or nil when it is not known or not a character.
    private static func decoded(_ name: String) -> String? {
        if name.hasPrefix("#") {
            let digits = name.dropFirst()
            let number = digits.hasPrefix("x") || digits.hasPrefix("X")
                ? UInt32(digits.dropFirst(), radix: 16)
                : UInt32(digits, radix: 10)
            guard let number, let scalar = Unicode.Scalar(number) else { return nil }
            return String(Character(scalar))
        }
        return namedEntities[name]
    }

    /// Runs of whitespace, including line breaks, become one space, and the ends are trimmed.
    static func collapsingWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
