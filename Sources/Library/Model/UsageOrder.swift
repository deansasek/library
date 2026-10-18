import Foundation

/// The Most Used and Recently Opened orders of the manager. The largest value comes first. Items never opened (or
/// opened zero times) go last, in the order they have in the tree, and so do items with equal values.
enum UsageOrder {
    /// Sorts `items` by `value`, largest first. A nil or zero value goes after every positive one.
    static func ordered<T>(_ items: [T], by value: (T) -> Double?) -> [T] {
        let ranked = items.enumerated().map { (index: $0.offset, item: $0.element, value: value($0.element)) }
        return ranked.sorted { a, b in
            switch (positive(a.value), positive(b.value)) {
            case let (x?, y?): return x != y ? x > y : a.index < b.index
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.index < b.index
            }
        }.map(\.item)
    }

    /// Items by how often they were opened, most first.
    static func mostUsed(_ items: [LibraryItem], counts: [String: Int]) -> [LibraryItem] {
        ordered(items) { counts[$0.id.uuidString].map(Double.init) }
    }

    /// Items by when they were last opened, most recent first.
    static func recentlyOpened(_ items: [LibraryItem], opened: [String: Date]) -> [LibraryItem] {
        ordered(items) { opened[$0.id.uuidString]?.timeIntervalSince1970 }
    }

    /// The open counts keyed by item id. They are stored keyed by the id's string, so this converts them once, and
    /// drops any key that is not an id.
    static func counts(byID stored: [String: Int]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for (key, count) in stored {
            if let id = UUID(uuidString: key) { counts[id] = count }
        }
        return counts
    }

    /// The items for Frequently Used: opened at least twice, most opened first, at most `limit` of them. Items opened
    /// equally often keep their tree order, as `ordered` does, so the list does not shuffle between runs.
    static func frequent(_ items: [LibraryItem], counts: [UUID: Int], limit: Int = 5) -> [LibraryItem] {
        items.enumerated()
            .filter { (counts[$0.element.id] ?? 0) >= 2 }
            .sorted { a, b in
                let left = counts[a.element.id] ?? 0, right = counts[b.element.id] ?? 0
                return left != right ? left > right : a.offset < b.offset
            }
            .prefix(limit).map(\.element)
    }

    /// Applies `order` to each run of nodes between dividers. Dividers keep their places, so no node moves across one.
    static func withinSections(_ nodes: [LibraryItem], _ order: ([LibraryItem]) -> [LibraryItem]) -> [LibraryItem] {
        var result: [LibraryItem] = []
        var section: [LibraryItem] = []
        for node in nodes {
            if node.isDivider == true {
                result += order(section)
                result.append(node)
                section = []
            } else {
                section.append(node)
            }
        }
        return result + order(section)
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }
}
