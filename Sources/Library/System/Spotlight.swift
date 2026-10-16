@preconcurrency import CoreSpotlight
import UniformTypeIdentifiers
import SwiftUI

enum Spotlight {
    /// Replaces the Spotlight entries with the bookmarks and apps in `nodes`. `done` gets true when the new entries were
    /// indexed, and false when Spotlight refused them, for example because indexing is off.
    static func index(_ nodes: [LibraryItem], done: @escaping @Sendable (Bool) -> Void = { _ in }) {
        let index = CSSearchableIndex.default()
        let items = indexable(nodes).map { node -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .item)
            attributes.title = node.name
            attributes.contentDescription = node.spotlightDescription
            attributes.keywords = "\(node.keywords ?? "") \(node.color ?? "")".split(separator: " ").map(String.init)
            return CSSearchableItem(uniqueIdentifier: node.id.uuidString, domainIdentifier: "library",
                                    attributeSet: attributes)
        }
        index.deleteSearchableItems(withDomainIdentifiers: ["bookmarks", "library"]) { _ in
            index.indexSearchableItems(items) { error in
                if let error { NSLog("Library: Spotlight did not index the items: \(error)") }
                done(error == nil)
            }
        }
    }

    /// The items Spotlight indexes: bookmarks and apps. A terminal command is never indexed, since its text is a shell command.
    static func indexable(_ nodes: [LibraryItem]) -> [LibraryItem] {
        nodes.filter { IntentLogic.isLaunchable($0) }
    }

    /// The host of a bookmark's address, such as "jira.example.com". The address may have no scheme, since a bookmark can
    /// be saved as "jira.example.com/browse". Nil when no host can be read.
    static func host(of address: String) -> String? {
        if let host = QuickOpenResult.link(from: address)?.host, !host.isEmpty { return host }
        // A template's braces are not valid in a URL, so the host is read from the text by hand.
        var text = Substring(address.trimmingCharacters(in: .whitespaces))
        if let range = text.range(of: "://") { text = text[range.upperBound...] }
        let authority = text.prefix { !"/?#".contains($0) }
        let hostAndPort = authority.split(separator: "@").last ?? ""
        let host = String(hostAndPort.split(separator: ":").first ?? "")
        return host.contains(".") && !host.contains(" ") ? host : nil
    }
}
