import CoreSpotlight
import UniformTypeIdentifiers
import SwiftUI

enum Spotlight {
    /// Replaces the Spotlight entries with the openable items in `nodes`.
    static func index(_ nodes: [LibraryItem]) {
        let index = CSSearchableIndex.default()
        let items = nodes.filter(\.isOpenable).map { node -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .item)
            attributes.title = node.name
            attributes.contentDescription = node.url ?? node.command ?? node.appPath
            attributes.keywords = "\(node.keywords ?? "") \(node.color ?? "")".split(separator: " ").map(String.init)
            return CSSearchableItem(uniqueIdentifier: node.id.uuidString, domainIdentifier: "library",
                                    attributeSet: attributes)
        }
        index.deleteSearchableItems(withDomainIdentifiers: ["bookmarks", "library"]) { _ in
            index.indexSearchableItems(items)
        }
    }
}
