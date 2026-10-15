import SwiftUI

struct ManageStateKey: FocusedValueKey {
    typealias Value = ManageState
}

extension FocusedValues {
    var manageState: ManageState? {
        get { self[ManageStateKey.self] }
        set { self[ManageStateKey.self] = newValue }
    }
}

/// File menu commands, active while the Library window is in front.
struct ManageCommands: Commands {
    let store: LibraryStore
    @FocusedValue(\.manageState) private var state

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            // These sheets belong to the Library window. With that window not in front, they are disabled, rather than
            // doing nothing when chosen.
            Button("New Bookmark…") { state?.present(.bookmark) }
                .keyboardShortcut("n")
                .disabled(state == nil)
            Button("New Application…") { state?.present(.application) }
                .disabled(state == nil)
            Button("New Terminal Command…") { state?.present(.terminal) }
                .disabled(state == nil)
            Button("New Folder…") { state?.present(.folder) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(state == nil)
            Button("New Divider…") { state?.present(.divider) }
                .disabled(state == nil)
            Button("New Snippet…") { SnippetEditorWindow.show(nil) }
            Divider()
            Button("Import Bookmarks…") { BookmarkImporter.run(into: store) }
            Button("Find Duplicates…") { state?.present(.duplicates) }
                .disabled(state == nil)
            Button { LinkChecker.checkNow(store: store) } label: { Text("Check Links", bundle: L10n.bundle) }
            Button("Export Library…") { LibraryBackupActions.export(store) }
            Divider()
            Button("Edit…") { state?.editSelection(in: store) }
                .keyboardShortcut("i")
                .disabled(state?.selection.isEmpty != false)
        }
    }
}
