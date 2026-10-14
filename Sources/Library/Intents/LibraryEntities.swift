import AppIntents

/// A bookmark or application in the library, as Shortcuts and Spotlight see it.
struct LibraryItemEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Library Item")
    static let defaultQuery = LibraryItemQuery()

    /// The item's id in the library, as text.
    let id: String
    let name: String
    let kind: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(kind)")
    }

    init(_ node: LibraryItem) {
        id = node.id.uuidString
        name = node.name
        kind = node.appPath != nil ? "Application" : "Bookmark"
    }
}

struct LibraryItemQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [LibraryItemEntity] {
        let nodes = LibraryStore.shared.nodes
        return identifiers
            .compactMap(UUID.init(uuidString:))
            .compactMap { nodes.node(withID: $0) }
            .filter(IntentLogic.isLaunchable)
            .map(LibraryItemEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [LibraryItemEntity] {
        let store = LibraryStore.shared
        return IntentLogic.launchables(matching: string, in: store.nodes, counts: store.openCounts)
            .map(LibraryItemEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [LibraryItemEntity] {
        let store = LibraryStore.shared
        return IntentLogic.launchables(matching: "", in: store.nodes, counts: store.openCounts)
            .prefix(25)
            .map(LibraryItemEntity.init)
    }
}

/// A terminal command in the library. Running one always asks first.
struct LibraryCommandEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Terminal Command")
    static let defaultQuery = LibraryCommandQuery()

    let id: String
    let name: String
    let command: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(command)")
    }

    init(_ node: LibraryItem) {
        id = node.id.uuidString
        name = node.name
        command = node.command ?? ""
    }
}

struct LibraryCommandQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [LibraryCommandEntity] {
        let nodes = LibraryStore.shared.nodes
        return identifiers
            .compactMap(UUID.init(uuidString:))
            .compactMap { nodes.node(withID: $0) }
            .filter(IntentLogic.canRunCommand)
            .map(LibraryCommandEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [LibraryCommandEntity] {
        IntentLogic.commands(in: LibraryStore.shared.nodes)
            .filter { $0.name.localizedCaseInsensitiveContains(string) || ($0.command ?? "").localizedCaseInsensitiveContains(string) }
            .map(LibraryCommandEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [LibraryCommandEntity] {
        IntentLogic.commands(in: LibraryStore.shared.nodes).map(LibraryCommandEntity.init)
    }
}
