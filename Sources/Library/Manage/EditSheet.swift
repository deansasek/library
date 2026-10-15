import SwiftUI

/// One form for every property of an item, like Get Info.
struct EditSheet: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject var state: ManageState
    let action: () -> Void

    private var node: LibraryItem { state.draft }
    private let browsers = installedBrowsers()

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $state.draft.name, prompt: Text("Required"))
                    LabeledContent("Icon") {
                        Button {
                            state.showIconPicker = true
                        } label: {
                            Label {
                                Text("Choose…")
                            } icon: {
                                Image(nsImage: store.icon(for: node))
                            }
                        }
                        .popover(isPresented: $state.showIconPicker) {
                            IconPicker(state: state, icon: $state.draft.icon) { state.showIconPicker = false }
                        }
                    }
                    if node.isDivider != true {
                        LabeledContent("Color") { colorSwatches }
                    }
                }
                if node.isOpenable {
                    Section {
                        TextField("Keywords", text: Binding(
                            get: { node.keywords ?? "" },
                            set: { state.draft.keywords = $0 }
                        ), prompt: Text("Optional"))
                        Toggle("Open When You Log In", isOn: Binding(
                            get: { node.openAtLogin == true },
                            set: { state.draft.openAtLogin = $0 ? true : nil }
                        ))
                    } footer: {
                        Text("Keywords find this item in Quick Open and Spotlight, such as “tix” for Jira. Items that open at login need Open at login turned on in Settings.")
                    }
                }
                if node.isOpenable {
                    Section {
                        LabeledContent(String(localized: "Notes", bundle: L10n.bundle)) {
                            TextEditor(text: Binding(
                                get: { node.note ?? "" },
                                set: { state.draft.note = $0 }
                            ))
                            .frame(minHeight: 72)
                        }
                    } footer: {
                        Text("Notes appear under the name in Quick Open and in Spotlight.", bundle: L10n.bundle)
                    }
                }
                details
                if node.isFolder {
                    Section {
                        Toggle(isOn: Binding(
                            get: { node.showsOpenAllItem },
                            set: { state.draft.showsOpenAll = $0 ? nil : false }
                        )) {
                            Text("Show Open All", bundle: L10n.bundle)
                        }
                    } footer: {
                        Text("Shows an Open All item for this folder in its menus. Turn this off to hide it.", bundle: L10n.bundle)
                    }
                }
                if node.isOpenable {
                    shortcuts
                }
            }
            .formStyle(.grouped)
            SheetButtons(state: state, action: action)
        }
        .frame(width: 440, height: height)
    }

    /// Tall forms scroll instead of growing past a laptop screen.
    private var height: CGFloat {
        let base: CGFloat
        if node.url != nil {
            base = node.isTemplate ? 845 : 765
        } else if node.appPath != nil {
            base = 805
        } else {
            base = node.command != nil ? 645 : (node.isFolder ? 370 : 230)
        }
        return min(base, 700)
    }

    private var colorSwatches: some View {
        HStack(spacing: 8) {
            ForEach(LibraryItem.tagNames, id: \.self) { name in
                Button {
                    state.draft.color = node.color == name ? nil : name
                } label: {
                    Circle()
                        .fill(Color(nsColor: LibraryItem.tagColors[name] ?? .gray))
                        .frame(width: 18, height: 18)
                        .overlay {
                            if node.color == name {
                                Circle().strokeBorder(Color.primary.opacity(0.6), lineWidth: 2).padding(-3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name.capitalized)
                .accessibilityAddTraits(node.color == name ? .isSelected : [])
            }
        }
    }

    private func linkStatusName(_ kind: LinkStatus.Kind) -> Text {
        switch kind {
        case .ok: Text("Working", bundle: L10n.bundle)
        case .broken: Text("Broken", bundle: L10n.bundle)
        case .unreachable: Text("Unreachable", bundle: L10n.bundle)
        case .unknown: Text("Not checked", bundle: L10n.bundle)
        }
    }

    @ViewBuilder
    private var details: some View {
        if node.url != nil {
            Section {
                TextField("URL", text: Binding(get: { node.url ?? "" }, set: { state.draft.url = $0 }), prompt: Text("Required"))
                Picker("Browser", selection: Binding(
                    get: { node.browser ?? "" },
                    set: { state.draft.browser = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Default Browser").tag("")
                    ForEach(browsers, id: \.id) { Text($0.name).tag($0.id) }
                }
                openInPicker
                Toggle("Ask for a value when opening", isOn: Binding(
                    get: { node.isTemplate },
                    set: { on in
                        let url = node.url ?? ""
                        state.draft.url = on ? url + "{}" : withoutPlaceholders(url, declared: node.templateFields)
                        if !on {
                            state.draft.templateFields = nil
                            state.fieldsText = ""
                        }
                    }
                ))
                if node.isTemplate {
                    TextField("Fields", text: Binding(
                        get: { state.fieldsText },
                        set: { text in
                            state.fieldsText = text
                            state.draft.templateFields = parseTemplateFields(text)
                        }
                    ), prompt: Text("Optional, such as query:Search"))
                    if node.placeholders.contains(where: { $0.name.isEmpty }) {
                        TextField("Prompt", text: Binding(
                            get: { node.promptLabel ?? "" },
                            set: { state.draft.promptLabel = $0 }
                        ), prompt: Text("Value"))
                    }
                    LabeledContent("Opens") {
                        Text(templatePreview(node.url ?? "", declared: node.templateFields))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                if let status = store.nodes.node(withID: node.id)?.linkStatus {
                    LabeledContent("Link status") { linkStatusName(status.kind) }
                    LabeledContent("Last checked") {
                        Text(status.checked.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                if node.isTemplate {
                    Text("Each value you enter replaces its placeholder. To ask for several values, name them in Fields, such as query:Search, and write {query} in the URL. Other braces are plain text.")
                }
            }
        } else if let path = node.appPath {
            Section {
                LabeledContent("Application") {
                    Text(path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                openInPicker
                TextField("Arguments", text: Binding(
                    get: { node.arguments ?? "" },
                    set: { state.draft.arguments = $0 }
                ), prompt: Text("Optional"))
                TextField("Terminal Command", text: Binding(
                    get: { node.command ?? "" },
                    set: { state.draft.command = $0 }
                ), prompt: Text("Optional"))
            } footer: {
                Text("With a terminal command, the item runs it in Terminal instead of opening the application.")
            }
        } else if node.command != nil {
            Section {
                TextField("Command", text: Binding(
                    get: { node.command ?? "" },
                    set: { state.draft.command = $0 }
                ))
            }
        }
    }

    @ViewBuilder
    private var openInPicker: some View {
        if let labels = node.modeLabels {
            Picker("Opens In", selection: Binding(
                get: { node.openNew == true },
                set: { state.draft.openNew = $0 ? true : nil }
            )) {
                Text(labels.existing).tag(false)
                Text(labels.new).tag(true)
            }
        }
    }

    private var shortcuts: some View {
        Section {
            ForEach((node.shortcuts ?? []).indices, id: \.self) { index in
                HStack {
                    ShortcutField(
                        shortcut: Binding(
                            get: { state.draft.shortcuts?.indices.contains(index) == true ? state.draft.shortcuts?[index] : nil },
                            set: { if let new = $0, index < (state.draft.shortcuts?.count ?? 0) { state.draft.shortcuts?[index] = new } }
                        ),
                        isRecording: state.recordingIndex == index,
                        setRecording: { state.recordingIndex = $0 ? index : nil },
                        clearable: false
                    )
                    Spacer()
                    if let labels = node.modeLabels {
                        Picker("Opens In", selection: Binding(
                            get: { state.draft.shortcuts?.indices.contains(index) == true ? state.draft.shortcuts?[index].openNew ?? false : false },
                            set: { if state.draft.shortcuts?.indices.contains(index) == true { state.draft.shortcuts?[index].openNew = $0 } }
                        )) {
                            Text(labels.existing).tag(false)
                            Text(labels.new).tag(true)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    Button("Remove", systemImage: "minus.circle") {
                        state.draft.shortcuts?.remove(at: index)
                        state.recordingIndex = nil
                        if state.draft.shortcuts?.isEmpty == true {
                            state.draft.shortcuts = nil
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
            }
            Button("Add Shortcut") {
                state.draft.shortcuts = (state.draft.shortcuts ?? []) + [Shortcut(modifiers: 0)]
                state.recordingIndex = (state.draft.shortcuts?.count ?? 1) - 1
            }
            if store.clickAccessMissing {
                LabeledContent("Click shortcuts need access") {
                    Button("Grant Access…") { HotKeys.requestClickAccess() }
                }
            }
        } header: {
            Text("Shortcuts")
        } footer: {
            Text("Click a shortcut, then press keys, or use a modified click, scroll, pinch, or swipe. Escape cancels. The … menu sets a hot corner.")
        }
    }
}
