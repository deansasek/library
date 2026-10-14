import SwiftUI

struct QuickOpenView: View {
    static let previewWidth: CGFloat = 280

    @ObservedObject var model: QuickOpenModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let close: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        let results = model.results
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Library Search", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.light))
                    .accessibilityLabel("Search Library")
                    .focused($focused)
                if !model.showActions, model.selected?.hasActions == true {
                    Button {
                        model.toggleActions()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Actions")
                            Text("⇥")
                                .foregroundStyle(.tertiary)
                        }
                        .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Show actions for the selected item (Tab)")
                    .accessibilityLabel("Actions")
                    .accessibilityHint("Shows actions for the selected item")
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 56)
            if !results.isEmpty {
                Divider()
                // The preview sits over the right side of the list's frame, so the list alone sets the card's height.
                Group {
                    if model.showActions {
                        actionsList
                    } else {
                        resultsList(results)
                    }
                }
                .padding(.trailing, Self.previewWidth + 1)
                .overlay(alignment: .trailing) {
                    HStack(spacing: 0) {
                        Divider()
                        preview(model.selected)
                    }
                    .frame(width: Self.previewWidth + 1)
                }
            }
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
        // A short fade and grow, like Spotlight. Reduce Motion turns the movement off.
        .opacity(model.appeared ? 1 : 0)
        .scaleEffect(model.appeared || reduceMotion ? 1 : 0.95)
        .animation(reduceMotion ? nil : .spring(response: 0.16, dampingFraction: 0.64), value: model.appeared)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            model.resetSelection()
        }
        .task {
            // The panel is not key yet when the view appears, so ask again once it is.
            for _ in 0..<5 where !focused {
                focused = true
                try? await Task.sleep(nanoseconds: 60_000_000)
            }
        }
        .onChange(of: model.query) { _, _ in model.resetSelection() }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func resultsList(_ results: [QuickOpenResult]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        if let title = result.section { header(title) }
                        row(result, index: index, selected: result.id == model.selection)
                            .id(result.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: model.selection) { _, id in
                if let id, !model.selectedByHover { proxy.scrollTo(id) }
            }
        }
        .frame(minHeight: 200, maxHeight: 340)
    }

    /// The selected result in full: all of a copied text, the picture, the files, or what a library item opens.
    private func preview(_ result: QuickOpenResult?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                previewContent(result)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }

    @ViewBuilder
    private func previewContent(_ result: QuickOpenResult?) -> some View {
        switch result?.kind {
        case .clip(let item)? where ClipboardLock.shared.isHidden(item):
            // A locked pinned item shows no text until the user authenticates here.
            Label {
                Text("Pinned Item", bundle: L10n.bundle)
            } icon: {
                Image(systemName: "lock.fill")
            }
            .font(.title3.weight(.semibold))
            Button {
                model.reveal(item)
            } label: {
                Text("Show Pinned Item", bundle: L10n.bundle)
            }
            Text(item.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        case .clip(let item)?:
            switch item.kind {
            case .image:
                if let image = model.previewImage {
                    AnimatedImageView(image: image)
                        .aspectRatio(image.size, contentMode: .fit)
                }
            case .file:
                ForEach(item.fileURLs, id: \.self) { url in
                    Label {
                        Text(url.lastPathComponent)
                    } icon: {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    }
                }
            case .other:
                Text("\(item.representations.first?.count ?? 0) formats")
                    .foregroundStyle(.secondary)
            default:
                Text(String((item.plainText ?? item.title).prefix(4000)))
                    .font(.callout)
                    .textSelection(.enabled)
            }
            Text("\(item.subtitle) · \(ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file))")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .item(let node, let folder)?:
            HStack(spacing: 10) {
                Image(nsImage: model.store.icon(for: node)).resizable().frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                Text(node.name).font(.title3.weight(.semibold))
            }
            Text(node.url ?? node.command ?? node.appPath ?? "")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if !folder.isEmpty {
                Text("In \(folder)").font(.caption).foregroundStyle(.secondary)
            }
        case .snippet(let snippet)?:
            Text(snippet.name).font(.title3.weight(.semibold))
            Text(String(snippet.text.prefix(4000)))
                .font(.callout)
                .textSelection(.enabled)
        case .some:
            Text(result?.title ?? "").font(.title3.weight(.semibold))
            Text(result?.subtitle ?? "").font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
        case nil:
            EmptyView()
        }
    }

    private var actionsList: some View {
        let actions = model.actions
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header("Actions for “\(model.selected?.title ?? "")”")
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    actionLabel(action)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(index == model.actionSelection ? Color(nsColor: .alternateSelectedControlTextColor) : Color.primary)
                        .background(index == model.actionSelection ? Color(nsColor: .selectedContentBackgroundColor) : .clear,
                                    in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.actionSelection = index
                            if action.children.isEmpty {
                                close()
                                action.run()
                            } else {
                                model.openGroup(action)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAddTraits(index == model.actionSelection ? .isSelected : [])
                }
            }
            .padding(8)
        }
        .frame(minHeight: 200, maxHeight: 340)
    }

    /// The action's title, with its symbol when it has one. Actions without a symbol keep plain text.
    @ViewBuilder
    private func actionLabel(_ action: QuickOpenAction) -> some View {
        if let icon = action.icon {
            Label(action.title, systemImage: icon)
        } else {
            Text(action.title)
        }
    }

    private func row(_ result: QuickOpenResult, index: Int, selected: Bool) -> some View {
        HStack(spacing: 10) {
            if let item = result.clip, let gif = model.animatedImage(for: item) {
                // A copied GIF plays in its thumbnail too.
                AnimatedImageView(image: gif)
                    .frame(width: 16, height: 16)
            } else {
                Image(nsImage: model.icon(for: result))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .lineLimit(1)
                if let note = result.noteLine {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(selected ? AnyShapeStyle(Color(nsColor: .alternateSelectedControlTextColor)) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(result.subtitle)
                    .font(.caption)
                    // System secondary colors adapt to light, dark, and Increase Contrast; selected rows keep the selected text color.
                    .foregroundStyle(selected ? AnyShapeStyle(Color(nsColor: .alternateSelectedControlTextColor)) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.callout)
                    .foregroundStyle(selected ? AnyShapeStyle(Color(nsColor: .alternateSelectedControlTextColor)) : AnyShapeStyle(.tertiary))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(selected ? Color(nsColor: .alternateSelectedControlTextColor) : Color.primary)
        .background(selected ? Color(nsColor: .selectedContentBackgroundColor) : .clear,
                    in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .onDrag { model.dragProvider(for: result) }
        .onContinuousHover { phase in
            if case .active = phase { model.hover(result.id) }
        }
        .onTapGesture {
            model.selection = result.id
            close()
            model.activate(flip: false)
        }
        .contextMenu {
            // Right-click shows the same actions as Tab.
            ForEach(model.actions(for: result)) { action in
                if action.children.isEmpty {
                    Button {
                        close()
                        action.run()
                    } label: {
                        actionLabel(action)
                    }
                } else {
                    Menu(action.title) {
                        ForEach(action.children) { child in
                            Button(child.title) {
                                close()
                                child.run()
                            }
                        }
                    }
                }
            }
        }
    }
}
