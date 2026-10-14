import SwiftUI

/// The fields of a snippet being added or edited. An object instead of `@State`, as the other forms do.
@MainActor
final class SnippetDraft: ObservableObject {
    let id: UUID
    let isNew: Bool
    @Published var name: String
    @Published var keywords: String
    @Published var text: String

    init(_ snippet: Snippet?) {
        id = snippet?.id ?? UUID()
        isNew = snippet == nil
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

/// The form for one snippet. Used in the Snippets sheet and in its own window from Quick Open and the File menu.
struct SnippetForm: View {
    @StateObject private var draft: SnippetDraft
    private let isNew: Bool
    /// Closes the form, after a save or a cancel.
    let close: () -> Void

    init(snippet: Snippet?, close: @escaping () -> Void) {
        _draft = StateObject(wrappedValue: SnippetDraft(snippet))
        isNew = snippet == nil
        self.close = close
    }

    var body: some View {
        VStack(spacing: 0) {
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
                    guard draft.isValid else { return }
                    if isNew {
                        SnippetStore.shared.add(draft.snippet)
                    } else {
                        SnippetStore.shared.update(draft.snippet)
                    }
                    close()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.isValid)
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
                .onTapGesture(count: 2) { model.editing = .edit(snippet.id) }
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
                Button("Edit…") {
                    if let id = model.selection { model.editing = .edit(id) }
                }
                .disabled(model.selection == nil)
                Button("Delete", role: .destructive) {
                    if let id = model.selection {
                        SnippetStore.shared.remove([id])
                        model.selection = nil
                    }
                }
                .disabled(model.selection == nil)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 480)
        .onExitCommand { dismiss() }
        .sheet(item: $model.editing) { editing in
            SnippetForm(snippet: editing.snippet(in: store.snippets)) { model.editing = nil }
        }
    }
}

/// The selection and the open editor of the Snippets sheet.
@MainActor
final class SnippetListModel: ObservableObject {
    enum Editing: Identifiable {
        case new
        case edit(UUID)

        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let id): return id.uuidString
            }
        }

        func snippet(in snippets: [Snippet]) -> Snippet? {
            guard case .edit(let id) = self else { return nil }
            return snippets.first { $0.id == id }
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
