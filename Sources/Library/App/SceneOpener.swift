import SwiftUI

/// Opens the window scenes that code outside a view opens, such as the welcome tour and the snippet editor. Only views
/// get SwiftUI's `openWindow` action, so the menu bar icon, which is always shown, passes it here. An open requested
/// before then waits for it.
@MainActor
enum SceneOpener {
    private static var openWindow: OpenWindowAction?
    private static var waiting: [String] = []

    static func register(_ action: OpenWindowAction) {
        openWindow = action
        let ids = waiting
        waiting = []
        for id in ids { action(id: id) }
    }

    static func open(_ id: String) {
        guard let openWindow else {
            if !waiting.contains(id) { waiting.append(id) }
            return
        }
        openWindow(id: id)
    }
}

/// The menu bar icon. It hands the window opener to `SceneOpener`.
struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label("Library", systemImage: "bookmark")
            .onAppear { SceneOpener.register(openWindow) }
    }
}
