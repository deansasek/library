import SwiftUI

/// Help menu commands. The guide lives in the project's README, so the menu opens it rather than duplicating it.
struct HelpCommands: Commands {
    let store: LibraryStore

    private static let readme = URL(string: "https://github.com/deansasek/library#readme")!
    private static let shortcuts = URL(string: "https://github.com/deansasek/library#shortcuts")!
    private static let issues = URL(string: "https://github.com/deansasek/library/issues/new")!

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Library Help") { NSWorkspace.shared.open(Self.readme) }
            Button("Keyboard Shortcuts") { NSWorkspace.shared.open(Self.shortcuts) }
            Divider()
            Button("Welcome Tour…") { Welcome.show(store: store) }
            Divider()
            Button("Report an Issue…") { NSWorkspace.shared.open(Self.issues) }
        }
    }
}
