import SwiftUI

/// Help menu commands. The guide lives in the project's README, so the menu opens it rather than duplicating it.
struct HelpCommands: Commands {
    let store: LibraryStore

    /// The guide is on the website, so it can be searched, linked, and read offline after the first visit.
    static let guide = URL(string: "https://deansasek.github.io/library-site/guide/")!
    static let shortcuts = URL(string: "https://deansasek.github.io/library-site/guide/find-and-open/#shortcuts")!
    static let issues = URL(string: "https://github.com/deansasek/library/issues/new")!
    static let support = URL(string: "https://buymeacoffee.com/deansasek")!

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Library Help") { NSWorkspace.shared.open(Self.guide) }
            Button("Keyboard Shortcuts") { NSWorkspace.shared.open(Self.shortcuts) }
            Divider()
            Button("Welcome Tour…") { Welcome.show() }
            Divider()
            Button("Report an Issue…") { NSWorkspace.shared.open(Self.issues) }
            Divider()
            Button("Support Library…") { NSWorkspace.shared.open(Self.support) }
        }
    }
}
