import SwiftUI

/// Edits several selected items at once. A field changes only when it is set. "Don't Change" leaves it alone.
struct BulkEditSheet: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject var state: ManageState

    private enum IconKind: Hashable {
        case keep, standard, custom
    }

    private var selected: [LibraryItem] { state.bulkIDs.compactMap { store.nodes.node(withID: $0) } }

    /// Names for Opens In. When the selection mixes bookmarks and applications, the names are generic.
    private var openLabels: (existing: String, new: String)? {
        let labels = selected.compactMap(\.modeLabels)
        guard let first = labels.first else { return nil }
        return labels.allSatisfy { $0.existing == first.existing } ? first : ("Existing", "New")
    }

    /// Dividers have no color, so the Color row only shows when some selected item can have one.
    private var canColor: Bool { selected.contains { $0.isDivider != true } }

    private var iconKind: Binding<IconKind> {
        Binding(
            get: {
                switch state.bulkEdit.icon {
                case .keep: return .keep
                case .clear: return .standard
                case .set: return .custom
                }
            },
            set: { kind in
                switch kind {
                case .keep:
                    state.bulkEdit.icon = .keep
                case .standard:
                    state.bulkEdit.icon = .clear
                case .custom:
                    if case .set = state.bulkEdit.icon { return }
                    state.bulkEdit.icon = .set("star.fill")
                }
            }
        )
    }

    /// The icon the picker chooses. Use Default in the picker clears the icon.
    private var iconChoice: Binding<String?> {
        Binding(
            get: {
                if case .set(let icon) = state.bulkEdit.icon { return icon }
                return nil
            },
            set: { state.bulkEdit.icon = $0.map { BulkChange<String>.set($0) } ?? .clear }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Icon") {
                        HStack {
                            Picker("Icon", selection: iconKind) {
                                Text("Don't Change").tag(IconKind.keep)
                                Text("Default").tag(IconKind.standard)
                                Text("Custom").tag(IconKind.custom)
                            }
                            .labelsHidden()
                            .fixedSize()
                            if iconKind.wrappedValue == .custom {
                                Button {
                                    state.showIconPicker = true
                                } label: {
                                    Text("Choose…")
                                }
                                .popover(isPresented: $state.showIconPicker) {
                                    IconPicker(state: state, icon: iconChoice) { state.showIconPicker = false }
                                }
                            }
                        }
                    }
                    if canColor {
                        Picker("Color", selection: $state.bulkEdit.color) {
                            Text("Don't Change").tag(BulkChange<String>.keep)
                            Text("None").tag(BulkChange<String>.clear)
                            ForEach(LibraryItem.tagNames, id: \.self) { name in
                                Text(name.capitalized).tag(BulkChange<String>.set(name))
                            }
                        }
                    }
                    if let labels = openLabels {
                        Picker("Opens In", selection: $state.bulkEdit.openNew) {
                            Text("Don't Change").tag(BulkChange<Bool>.keep)
                            Text(labels.existing).tag(BulkChange<Bool>.set(false))
                            Text(labels.new).tag(BulkChange<Bool>.set(true))
                        }
                    }
                } footer: {
                    Text("Only the fields you change are applied to the \(selected.count) selected items. Opens In applies to bookmarks and applications.")
                }
            }
            .formStyle(.grouped)
            buttons
        }
        .frame(width: 440)
    }

    private var buttons: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { state.sheet = nil }
                .keyboardShortcut(.cancelAction)
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(state.bulkEdit.changesNothing)
        }
        .padding([.horizontal, .bottom], 20)
    }

    /// Applies every changed field as one undoable step.
    private func save() {
        let edit = state.bulkEdit
        let ids = state.bulkIDs
        store.perform("Edit Items") { $0 = BulkEdit.apply(edit, to: ids, in: $0) }
        state.sheet = nil
    }
}
