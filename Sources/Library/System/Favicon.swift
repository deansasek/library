import ImageIO
import SwiftUI

enum Favicon {
    private static let cacheDir = LibraryStore.dir.appendingPathComponent("favicons")
    /// Responses larger than this are rejected. A favicon is small, so a bigger response is not one.
    static let maxBytes = 512 * 1024
    /// A host that gave no icon is not asked again for this long, so a dead site is not retried on every launch.
    static let failureWindow: TimeInterval = 24 * 60 * 60
    private static let failuresKey = "faviconFailures"

    static func load(for url: URL) async -> NSImage? {
        guard let host = url.host else { return nil }
        let cached = cacheDir.appendingPathComponent("\(host).png")
        if let data = try? Data(contentsOf: cached), let image = sized(NSImage(data: data)) {
            return image
        }
        guard !hasRecentFailure(host: host) else { return nil }
        guard let data = await fetch(from: url),
              let image = NSImage(data: data),
              let png = pngData(image) else {
            // A cancelled load says nothing about the site, so it is not remembered.
            if !Task.isCancelled { recordFailure(host: host) }
            return nil
        }
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try? png.write(to: cached)
        return sized(image)
    }

    /// Tries `/favicon.ico`, which is small, and reads the page for its `<link rel="icon">` only if that fails.
    private static func fetch(from url: URL) async -> Data? {
        if let root = URL(string: "/favicon.ico", relativeTo: url)?.absoluteURL, let data = await image(at: root) {
            return data
        }
        guard let (html, _) = await get(url), let text = String(data: html, encoding: .utf8),
              let href = iconHref(in: text), let iconURL = URL(string: href, relativeTo: url)?.absoluteURL else { return nil }
        return await image(at: iconURL)
    }

    private static func image(at url: URL) async -> Data? {
        guard let (data, response) = await get(url), response.statusCode == 200,
              NSImage(data: data) != nil, pixelsAllowed(data) else { return nil }
        return data
    }

    /// Downloads at most `maxBytes`, so an oversized response is never held in memory in full. The download stops
    /// when the limit is passed. Only http and https addresses are read, so a page cannot point the icon at a
    /// local file. The 10 s timeout is unchanged.
    private static func get(_ url: URL) async -> (data: Data, response: HTTPURLResponse)? {
        await WebFetch.fetch(url, limit: maxBytes)
    }

    /// The largest picture a favicon may decode to. A small file can declare a huge picture, so the size is read
    /// from its header before the picture is decoded.
    static let maxPixelSide = 4096

    /// Whether the picture's header declares a size a favicon could have. Formats without a pixel size (vector
    /// files) are allowed, since they do not expand in memory the way a bitmap does.
    static func pixelsAllowed(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return true }
        return pixelSizeAllowed(width: width, height: height)
    }

    /// Whether a picture of this size may be decoded.
    static func pixelSizeAllowed(width: Int, height: Int) -> Bool {
        width > 0 && height > 0 && width <= maxPixelSide && height <= maxPixelSide
    }

    /// The failure timestamps still inside the window. Timestamps in the future (after a clock change) are dropped too.
    static func pruned(_ failures: [String: TimeInterval], now: TimeInterval) -> [String: TimeInterval] {
        failures.filter { entry in
            let age = now - entry.value
            return age >= 0 && age < failureWindow
        }
    }

    /// Reads the stored failures, drops expired ones, and writes back only when something was dropped.
    private static func recentFailures(now: Date = .now) -> [String: TimeInterval] {
        let stored = UserDefaults.standard.dictionary(forKey: failuresKey) as? [String: TimeInterval] ?? [:]
        let kept = pruned(stored, now: now.timeIntervalSince1970)
        if kept.count != stored.count {
            UserDefaults.standard.set(kept, forKey: failuresKey)
        }
        return kept
    }

    private static func hasRecentFailure(host: String) -> Bool {
        recentFailures()[host] != nil
    }

    private static func recordFailure(host: String) {
        var failures = recentFailures()
        failures[host] = Date.now.timeIntervalSince1970
        UserDefaults.standard.set(failures, forKey: failuresKey)
    }

    /// The most characters of a page that are searched for an icon link. Icon links sit in the head.
    static let iconSearchLimit = 64 * 1024

    /// The `href` of the page's icon link, read from its first 64 KB. Each attribute scan is bounded, so a tag that
    /// never closes costs a fixed amount of work and cannot stall the parse.
    static func iconHref(in html: String) -> String? {
        let head = String(html.prefix(iconSearchLimit))
        let pattern = #"<link[^>]{0,500}?rel=["'](?:shortcut )?icon["'][^>]{0,500}?href=["']([^"']{1,2048})["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: head, range: NSRange(head.startIndex..., in: head)),
              let range = Range(match.range(at: 1), in: head) else { return nil }
        return String(head[range])
    }

    private static func sized(_ image: NSImage?) -> NSImage? {
        image?.size = NSSize(width: 16, height: 16)
        return image
    }

    private static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
