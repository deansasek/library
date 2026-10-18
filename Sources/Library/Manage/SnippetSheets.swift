import SwiftUI

/// The fields of a snippet being added or edited. An object instead of `@State`, as the other forms do.
@MainActor
final class SnippetDraft: ObservableObject {
    let id: UUID
    let isNew: Bool
    @Published var name: String
    @Published var keywords: String
    @Published var text: String
    /// The snippet as the editor opened it, or nil for a new snippet. A save compares the edit with it.
    let original: Snippet?

    init(_ snippet: Snippet?) {
        id = snippet?.id ?? UUID()
        isNew = snippet == nil
        original = snippet
        name = snippet?.name ?? ""
        keywords = snippet?.keywords ?? ""
        text = snippet?.text ?? ""
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var snippet: Snippet {
        let trimmedKeywords = keywords.trimmingCharacters(in: .whitespaces)
        return Snippet(id: id, name: name.trimmingCharacters(in: .whitespaces), text: text,
                       keywords: trimmedKeywords.isEmpty ? nil : trimmedKeywords)
    }
}

/// A notice above the snippet lists and forms, such as that saving is blocked.
struct SnippetNotice: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
    }
}

/// The form for one snippet. Used in the Snippets sheet and in its own window from Quick Open and the File menu.
struct SnippetForm: View {
    @StateObject private var draft: SnippetDraft
    @ObservedObject private var store = SnippetStore.shared
    private let isNew: Bool
    /// Closes the form, after a save or a cancel.
    let close: () -> Void

    init(snippet: Snippet?, close: @escaping () -> Void) {
        _draft = StateObject(wrappedValue: SnippetDraft(snippet))
        isNew = snippet == nil
        self.close = close
    }

    /// The snippet was removed in another window. Its text stays on screen, so it can be copied, but it cannot be saved.
    private var isRemoved: Bool {
        !isNew && !store.snippets.contains { $0.id == draft.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.saveBlocked {
                SnippetNotice(message: "snippets.json cannot be read, so snippets cannot be saved. Check the file in your library folder.")
            } else if isRemoved {
                SnippetNotice(message: "This snippet was removed in another window, so these changes cannot be saved. Copy the text before closing.")
            }
            Form {
                Section {
                    TextField("Name", text: $draft.name, prompt: Text("Required"))
                    TextField("Keywords", text: $draft.keywords, prompt: Text("Optional"))
                } footer: {
                    Text("Keywords find the snippet in Quick Open, such as “address” for your street address.")
                }
                Section {
                    TextEditor(text: $draft.text)
                        .frame(minHeight: 140)
                        .accessibilityLabel("Text")
                } header: {
                    Text("Text")
                } footer: {
                    Text("Return in Quick Open copies this text. Snippets are saved in snippets.json in your library folder. They are not encrypted and are not part of clipboard history.")
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { close() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") {
                    guard draft.isValid, !store.saveBlocked, !isRemoved else { return }
                    if isNew {
                        SnippetStore.shared.add(draft.snippet)
                    } else if let original = draft.original {
                        guard SnippetStore.shared.update(draft.snippet, changedFrom: original) else { return }
                    }
                    close()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.isValid || store.saveBlocked || isRemoved)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 440)
    }
}

/// The Snippets sheet of the manager window: every snippet, with Add, Edit, and Delete.
struct SnippetsSheet: View {
    @ObservedObject private var store = SnippetStore.shared
    @StateObject private var model = SnippetListModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager

    /// True while the delete confirmation asked by the Delete button or the Delete key is on screen.
    private var deleteIsPresented: Binding<Bool> {
        Binding(
            get: { model.pendingDelete != nil },
            set: { if !$0 { model.pendingDelete = nil } }
        )
    }

    /// Asks before removing the selected snippet. A snippet has no Recently Deleted copy, so both the button and the
    /// Delete key confirm first; Undo right after the confirmation brings it back.
    private func requestDelete() {
        guard let id = model.selection, !store.saveBlocked else { return }
        model.pendingDelete = id
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.saveBlocked {
                SnippetNotice(message: "snippets.json cannot be read, so snippets cannot be saved. Check the file in your library folder.")
                Divider()
            }
            List(store.snippets, selection: $model.selection) { snippet in
                VStack(alignment: .leading, spacing: 1) {
                    Text(snippet.name)
                        .lineLimit(1)
                    Text(snippet.text.split(whereSeparator: \.isNewline).joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .tag(snippet.id)
                .onTapGesture(count: 2) { model.editing = .edit(snippet) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .frame(height: 300)
            .overlay {
                if store.snippets.isEmpty {
                    ContentUnavailableView {
                        Label("No Snippets", systemImage: "text.quote")
                    } description: {
                        Text("Add text you type often, such as an address or a standard reply.")
                    } actions: {
                        Button("Add Snippet") { model.editing = .new }
                    }
                }
            }
            // Return opens the selected snippet for editing, as Return renames in the Edit Library list.
            .onKeyPress(.return) {
                guard let id = model.selection, let snippet = store.snippets.first(where: { $0.id == id }) else { return .ignored }
                model.editing = .edit(snippet)
                return .handled
            }
            // Delete (Backspace) asks first: unlike a bookmark, a snippet has no Recently Deleted copy to restore.
            .onDeleteCommand { requestDelete() }
            Divider()
            HStack {
                // The label is the visible text, so Voice Control can click it by the name on screen.
                Button("Add…") { model.editing = .new }
                    .disabled(store.saveBlocked)
                Button("Edit…") {
                    if let id = model.selection, let snippet = store.snippets.first(where: { $0.id == id }) {
                        model.editing = .edit(snippet)
                    }
                }
                .disabled(model.selection == nil)
                Button("Delete", role: .destructive) { requestDelete() }
                    .disabled(model.selection == nil || store.saveBlocked)
                Spacer()
                // Done is not the default button: Return in the list opens the selected snippet for editing.
                Button("Done") { dismiss() }
            }
            .padding(20)
        }
        .frame(width: 480)
        // The sheet's undo manager, so a Delete registers one step that Undo (⌘Z) takes back from here or the menu.
        .onAppear { store.undoManager = undoManager }
        .onExitCommand { dismiss() }
        .confirmationDialog("Delete Snippet?", isPresented: deleteIsPresented, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = model.pendingDelete {
                    SnippetStore.shared.remove([id])
                    model.selection = nil
                }
                model.pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { model.pendingDelete = nil }
        } message: {
            Text("The snippet is removed from snippets.json. Undo right after this brings it back.")
        }
        .sheet(item: $model.editing) { editing in
            SnippetForm(snippet: editing.snippet) { model.editing = nil }
        }
    }
}

/// The selection and the open editor of the Snippets sheet.
@MainActor
final class SnippetListModel: ObservableObject {
    enum Editing: Identifiable {
        case new
        /// The snippet as it was when its editor opened. Its editor keeps this copy even if the snippet is removed.
        case edit(Snippet)

        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let snippet): return snippet.id.uuidString
            }
        }

        var snippet: Snippet? {
            guard case .edit(let snippet) = self else { return nil }
            return snippet
        }
    }

    @Published var selection: UUID?
    @Published var editing: Editing?
    /// The snippet a Delete button or Delete key asked to remove, while the confirmation is on screen.
    @Published var pendingDelete: UUID?
}

/// Opens one snippet form in its own window: File > New Snippet, and Edit in Quick Open. The window is single-instance,
/// so an editor that is already open is brought forward with the text it holds, which may not be saved yet.
@MainActor
enum SnippetEditorWindow {
    static let windowID = "snippet"
    /// The snippet the window's form opens with. Nil is a new snippet.
    private(set) static var snippet: Snippet?

    static func show(_ snippet: Snippet?) {
        self.snippet = snippet
        SceneOpener.open(windowID)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// The content of the snippet editor window scene.
struct SnippetEditorScene: View {
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        let snippet = SnippetEditorWindow.snippet
        SnippetForm(snippet: snippet) { dismissWindow(id: SnippetEditorWindow.windowID) }
            .navigationTitle(snippet == nil ? "New Snippet" : "Edit Snippet")
    }
}
