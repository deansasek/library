import SwiftUI

@main
struct LibraryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let store = LibraryStore.shared

    init() {
        // Before any view reads the setting, so a launch with no stored choice starts with the automatic checks on.
        UpdateCheck.registerDefaults()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            MenuBarLabel()
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
        .commands {
            ManageCommands(store: store)
            HelpCommands(store: store)
        }
        Window("Welcome to Library", id: Welcome.windowID) {
            WelcomeScene()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .handlesExternalEvents(matching: [])
        Window("Snippet", id: SnippetEditorWindow.windowID) {
            SnippetEditorScene()
        }
        .windowResizability(.contentSize)
        // The form's text belongs to the snippet it was opened for, so the window does not reopen on launch.
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        .handlesExternalEvents(matching: [])
        Settings {
            SettingsView(store: store)
        }
    }
}
