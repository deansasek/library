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
            Button("New Bookmark…") { state?.present(.bookmark) }
                .keyboardShortcut("n")
            Button("New Application…") { state?.present(.application) }
            Button("New Terminal Command…") { state?.present(.terminal) }
            Button("New Folder…") { state?.present(.folder) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Divider…") { state?.present(.divider) }
            Divider()
            Button("Edit…") {
                if let state, let id = state.selection.first { state.edit(id, in: store) }
            }
            .keyboardShortcut("i")
            .disabled(state?.selection.count != 1)
        }
    }
}
