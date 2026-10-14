import SwiftUI

@main
struct LibraryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let store = LibraryStore.shared

    var body: some Scene {
        MenuBarExtra("Library", systemImage: "bookmark") {
            MenuContent(store: store)
        }
        Window("Library", id: "manage") {
            ManageView(store: store)
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        // A menu bar app starts with no window.
        .defaultLaunchBehavior(.suppressed)
        // Opening a library:// link must not open the window. The app delegate handles it.
        .handlesExternalEvents(matching: [])
        .commands { ManageCommands(store: store) }
        Settings {
            SettingsView(store: store)
        }
    }
}
