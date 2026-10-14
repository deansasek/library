import SwiftUI

/// Removes tracking parameters from a link. Only the copy changes: the link saved in the library is not touched.
enum TrackingParameters {
    /// Parameters that exist only to track where a click came from. Compared in lowercase.
    static let names: Set<String> = ["fbclid", "gclid", "mc_eid", "mc_cid", "igshid", "ref_src"]
    /// Any parameter that starts with one of these, such as `utm_source`.
    static let prefixes = ["utm_"]

    static func isTracking(_ name: String) -> Bool {
        let name = name.lowercased()
        return names.contains(name) || prefixes.contains { name.hasPrefix($0) }
    }

    /// The link without its tracking parameters. Every other part is kept as written: the other parameters, their
    /// encoding, and the fragment. A link with no tracking parameter comes back unchanged.
    static func clean(_ link: String) -> String {
        let end = link.firstIndex(of: "#") ?? link.endIndex
        guard let mark = link[..<end].firstIndex(of: "?") else { return link }
        let query = link[link.index(after: mark)..<end]
        let fragment = String(link[end...])
        let pieces = query.split(separator: "&", omittingEmptySubsequences: true)
        let kept = pieces.filter { piece in !isTracking(String(piece.prefix { $0 != "=" })) }
        guard kept.count != pieces.count else { return link }
        let base = String(link[..<mark])
        return kept.isEmpty ? base + fragment : base + "?" + kept.joined(separator: "&") + fragment
    }
}

/// The setting in Settings > General. On by default. It only changes what copying a link puts on the clipboard.
@MainActor
final class TrackingPreferences: ObservableObject {
    static let shared = TrackingPreferences()

    @Published var removesOnCopy: Bool {
        didSet { UserDefaults.standard.set(removesOnCopy, forKey: "removesTrackingParameters") }
    }

    private init() {
        removesOnCopy = UserDefaults.standard.object(forKey: "removesTrackingParameters") as? Bool ?? true
    }
}
