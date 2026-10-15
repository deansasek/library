@preconcurrency import CoreSpotlight
import UniformTypeIdentifiers
import SwiftUI

enum Spotlight {
    /// Replaces the Spotlight entries with the openable items in `nodes`. `done` gets true when the new entries were
    /// indexed, and false when Spotlight refused them, for example because indexing is off.
    static func index(_ nodes: [LibraryItem], done: @escaping @Sendable (Bool) -> Void = { _ in }) {
        let index = CSSearchableIndex.default()
        let items = nodes.filter(\.isOpenable).map { node -> CSSearchableItem in
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
}
