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
            Divider()
            HStack {
                Button("Add…") { model.editing = .new }
                    .accessibilityLabel("Add Snippet")
                    .disabled(store.saveBlocked)
                Button("Edit…") {
                    if let id = model.selection, let snippet = store.snippets.first(where: { $0.id == id }) {
                        model.editing = .edit(snippet)
                    }
                }
                .disabled(model.selection == nil)
                Button("Delete", role: .destructive) {
                    if let id = model.selection {
                        SnippetStore.shared.remove([id])
                        model.selection = nil
                    }
                }
                .disabled(model.selection == nil || store.saveBlocked)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 480)
        .onExitCommand { dismiss() }
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
}

/// Opens one snippet form in its own window: File > New Snippet, and Edit in Quick Open.
@MainActor
enum SnippetEditorWindow {
    private static var window: NSWindow?

    static func show(_ snippet: Snippet?) {
        window?.close()
        let window = NSWindow(contentViewController: NSHostingController(
            rootView: SnippetForm(snippet: snippet) { SnippetEditorWindow.window?.close() }))
        window.title = snippet == nil ? "New Snippet" : "Edit Snippet"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}
