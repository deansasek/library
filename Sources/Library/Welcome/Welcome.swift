import SwiftUI

@MainActor
enum Welcome {
    private static var window: NSWindow?

    /// Shows the welcome window once, the first time this version runs.
    @MainActor
    static func showIfNeeded(store: LibraryStore) {
        guard !UserDefaults.standard.bool(forKey: "welcomeShown2") else { return }
        UserDefaults.standard.set(true, forKey: "welcomeShown2")
        show(store: store)
    }

    @MainActor
    static func show(store: LibraryStore, page: Int = 0) {
        window?.close()
        let model = WelcomeModel(page: page)
        let window = NSWindow(contentViewController: NSHostingController(
            rootView: WelcomeView(store: store, model: model) { Welcome.window?.close() }))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Welcome to Library"  // not shown, but VoiceOver reads it
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        Welcome.window = window
    }
}
