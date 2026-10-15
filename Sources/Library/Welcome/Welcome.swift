import SwiftUI

/// The welcome tour, in the app's `Welcome to Library` window scene. The window is single-instance: showing the tour
/// while it is open brings it forward and moves it to the chosen page.
@MainActor
enum Welcome {
    static let windowID = "welcome"
    /// The page the window shows. Shared, so showing the tour again changes the page of the window that is open.
    static let model = WelcomeModel()

    /// Shows the welcome window once, the first time this version runs.
    static func showIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "welcomeShown2") else { return }
        UserDefaults.standard.set(true, forKey: "welcomeShown2")
        show()
    }

    static func show(page: Int = 0) {
        model.reset(page: page)
        SceneOpener.open(windowID)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// The content of the welcome window scene.
struct WelcomeScene: View {
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        WelcomeView(store: LibraryStore.shared, model: Welcome.model) { dismissWindow(id: Welcome.windowID) }
            .background(WindowChrome { window in
                // The tour has no minimize or zoom button, and the window moves from its background.
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
                window.isMovableByWindowBackground = true
            })
    }
}

/// Hands the window that holds this view to `configure`, for the few settings a window scene has no modifier for.
struct WindowChrome: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> ChromeView {
        ChromeView(configure: configure)
    }

    func updateNSView(_ nsView: ChromeView, context: Context) {}

    final class ChromeView: NSView {
        private let configure: (NSWindow) -> Void

        init(configure: @escaping (NSWindow) -> Void) {
            self.configure = configure
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { configure(window) }
        }
    }
}
