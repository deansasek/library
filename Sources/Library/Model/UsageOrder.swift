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

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }
}
