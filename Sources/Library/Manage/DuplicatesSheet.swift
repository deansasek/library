import SwiftUI

/// Lists the bookmarks and applications that open the same link or application. Choose the one to keep in each group.
struct DuplicatesSheet: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject var state: ManageState

    private var groups: [Duplicates.Group] { Duplicates.groups(in: store.nodes) }

    var body: some View {
        VStack(spacing: 0) {
            if groups.isEmpty {
                ContentUnavailableView {
                    Label("No Duplicates", systemImage: "checkmark.circle")
                } description: {
                    Text("No two bookmarks or applications open the same link or application.")
                }
                .frame(height: 260)
            } else {
                Form {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.items) { item in
                                row(item, in: group)
                            }
                        } header: {
                            Text(group.isApp ? "Same application" : "Same link")
                        }
                    }
                }
                .formStyle(.grouped)
                .frame(height: 420)
            }
            buttons
        }
        .frame(width: 520)
        .onExitCommand { state.sheet = nil }
    }

    private func row(_ item: LibraryItem, in group: Duplicates.Group) -> some View {
        let kept = (state.keepChoices[group.id] ?? group.items[0].id) == item.id
        let folder = Duplicates.folderTitle(of: item.id, in: store.nodes) ?? ""
        return Button {
            state.keepChoices[group.id] = item.id
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: kept ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(kept ? Color.accentColor : Color.secondary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                    Text(folder)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.url ?? item.appPath ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(kept ? .isSelected : [])
    }

    private var buttons: some View {
        HStack {
            Spacer()
            if groups.isEmpty {
                Button("Done") { state.sheet = nil }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel", role: .cancel) { state.sheet = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Merge", role: .destructive) { merge() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    /// Removes the items that were not chosen, as one undoable step.
    private func merge() {
        let choices = state.keepChoices
        let outcome = store.mergeDuplicates(keeping: choices)
        state.selection = state.selection.intersection(Set(store.nodes.allIDs))
        state.sheet = nil
        state.mergeSummary = outcome?.summary
    }
}
