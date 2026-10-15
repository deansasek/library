import SwiftUI

/// Sheet for new bookmarks, terminal commands, folders, and dividers.
struct AddSheet: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject var state: ManageState
    let action: () -> Void
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $state.name, prompt: Text("Required"))
                    .focused($nameFocused)
                switch state.sheet {
                case .bookmark:
                    TextField("URL", text: $state.url, prompt: Text("Required"))
                case .terminal:
                    TextField("Command", text: $state.command, prompt: Text("Required"))
                case .folder:
                    Section {
                        Toggle(isOn: $state.showsOpenAll) {
                            Text("Show Open All", bundle: L10n.bundle)
                        }
                    } footer: {
                        Text("Shows an Open All item for this folder in its menus. Turn this off to hide it.", bundle: L10n.bundle)
                    }
                default:
                    EmptyView()
                }
                FolderPicker(store: store, state: state)
            }
            .formStyle(.grouped)
            SheetButtons(state: state, action: action)
        }
        .frame(width: 400)
        .onAppear { nameFocused = true }
    }
}

struct AppPickerSheet: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject var state: ManageState
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search", text: $state.search)
                .textFieldStyle(.roundedBorder)
                .padding([.horizontal, .top], 20)
                .padding(.bottom, 12)

            List(state.filteredApps, selection: $state.appSelection) { app in
                Label {
                    Text(app.name)
                } icon: {
                    Image(nsImage: appIcon(at: app.path))
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .frame(height: 280)
            .overlay {
                if state.apps.isEmpty {
                    ProgressView()
                        .accessibilityLabel(String(localized: "Loading applications", bundle: L10n.bundle))
                }
            }

            Form {
                TextField("Arguments", text: $state.arguments, prompt: Text("Optional"))
                FolderPicker(store: store, state: state)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 130)

            SheetButtons(state: state, action: action)
        }
        .frame(width: 420)
        .task {
            if state.apps.isEmpty {
                state.apps = await Task.detached { InstalledApp.scan() }.value
            }
        }
    }
}

struct FolderPicker: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject var state: ManageState

    var body: some View {
        Picker("Folder", selection: $state.folderID) {
            Text("Top level").tag(UUID?.none)
            ForEach(store.nodes.folders()) { folder in
                Text(folder.title).tag(UUID?.some(folder.id))
            }
        }
    }
}

struct SheetButtons: View {
    @ObservedObject var state: ManageState
    let action: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { state.sheet = nil }
                .keyboardShortcut(.cancelAction)
            Button(isEdit ? "Save" : "Add") {
                guard state.isValid else { return }
                action()
                state.sheet = nil
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!state.isValid)
        }
        .padding([.horizontal, .bottom], 20)
    }

    private var isEdit: Bool {
        if case .edit = state.sheet { return true }
        return false
    }
}
