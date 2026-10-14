import SwiftUI

enum Favicon {
    private static let cacheDir = LibraryStore.dir.appendingPathComponent("favicons")

    static func load(for url: URL) async -> NSImage? {
        guard let host = url.host else { return nil }
        let cached = cacheDir.appendingPathComponent("\(host).png")
        if let data = try? Data(contentsOf: cached), let image = sized(NSImage(data: data)) {
            return image
        }
        guard let data = await fetch(from: url),
              let image = NSImage(data: data),
              let png = pngData(image) else { return nil }
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
        guard let (data, response) = await get(url), (response as? HTTPURLResponse)?.statusCode == 200,
              NSImage(data: data) != nil else { return nil }
        return data
    }

    private static func get(_ url: URL) async -> (Data, URLResponse)? {
        try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10))
    }

    private static func iconHref(in html: String) -> String? {
        let pattern = #"<link[^>]*rel=["'](?:shortcut )?icon["'][^>]*href=["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
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
