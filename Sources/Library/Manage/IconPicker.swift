import SwiftUI

/// Popover with Symbols and Emoji tabs, each a searchable grid.
struct IconPicker: View {
    @ObservedObject var state: ManageState
    /// The icon that choosing a grid cell sets. Nil means the default icon.
    let icon: Binding<String?>
    /// Called after a choice, to close the popover.
    let dismiss: () -> Void

    private static let recentsKey = "recentEmoji"

    private static let symbols = [
        "star.fill", "heart.fill", "bookmark.fill", "flag.fill", "tag.fill", "bell.fill", "bolt.fill",
        "flame.fill", "leaf.fill", "moon.fill", "sun.max.fill", "cloud.fill", "drop.fill", "snowflake",
        "globe", "network", "link", "safari", "envelope.fill", "phone.fill", "message.fill",
        "bubble.left.fill", "video.fill", "camera.fill", "photo.fill", "music.note", "play.fill",
        "headphones", "mic.fill", "book.fill", "books.vertical.fill", "newspaper.fill", "doc.fill",
        "doc.text.fill", "folder.fill", "tray.fill", "archivebox.fill", "paperclip", "pencil",
        "highlighter", "scissors", "ruler.fill", "hammer.fill", "wrench.and.screwdriver.fill",
        "gearshape.fill", "slider.horizontal.3", "terminal.fill", "curlybraces", "cpu.fill",
        "externaldrive.fill", "server.rack", "desktopcomputer", "laptopcomputer", "display",
        "keyboard.fill", "printer.fill", "wifi", "lock.fill", "key.fill", "shield.fill", "eye.fill",
        "magnifyingglass", "chart.bar.fill", "chart.pie.fill", "chart.line.uptrend.xyaxis",
        "creditcard.fill", "dollarsign.circle.fill", "banknote.fill", "cart.fill", "bag.fill",
        "gift.fill", "house.fill", "building.2.fill", "map.fill", "location.fill", "car.fill",
        "airplane", "bicycle", "calendar", "clock.fill", "timer", "alarm.fill",
        "checkmark.circle.fill", "xmark.circle.fill", "exclamationmark.triangle.fill",
        "questionmark.circle.fill", "info.circle.fill", "person.fill", "person.2.fill",
        "graduationcap.fill", "briefcase.fill", "lightbulb.fill", "puzzlepiece.fill",
        "gamecontroller.fill", "sparkles", "paintbrush.fill", "cup.and.saucer.fill", "fork.knife",
        "pawprint.fill",
    ].filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }

    /// Single-scalar emoji from the Unicode tables, faces first, with their Unicode names for search.
    private static let emoji: [(symbol: String, name: String)] = {
        let ranges: [ClosedRange<UInt32>] = [
            0x1F600...0x1F64F, 0x1F910...0x1F9FF, 0x1F300...0x1F5FF,
            0x1F680...0x1F6FF, 0x1FA70...0x1FAFF, 0x2600...0x27BF, 0x2B00...0x2BFF,
        ]
        return ranges.flatMap { $0 }.compactMap { value in
            guard let scalar = Unicode.Scalar(value), scalar.properties.isEmojiPresentation,
                  !(0x1F3FB...0x1F3FF).contains(value), let name = scalar.properties.name else { return nil }
            return (String(scalar), name.lowercased())
        }
    }()

    /// Each emoji's name, so VoiceOver can say what a button is.
    private static let emojiNames = Dictionary(uniqueKeysWithValues: emoji.map { ($0.symbol, $0.name) })

    private var query: String { state.iconSearch.trimmingCharacters(in: .whitespaces).lowercased() }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Icon type", selection: $state.iconTab) {
                ForEach(IconTab.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TextField("Search", text: $state.iconSearch)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                if state.iconTab == .symbols {
                    grid(Self.symbols.filter { query.isEmpty || $0.contains(query) },
                         label: { $0.replacingOccurrences(of: ".", with: " ") }) { name in
                        Image(systemName: name)
                    }
                } else {
                    emojiGrids
                }
            }
            .frame(height: 220)
            HStack {
                Spacer()
                Button("Use Default") { choose(nil) }
            }
        }
        .padding()
        .frame(width: 320)
    }

    @ViewBuilder
    private var emojiGrids: some View {
        let recents = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []
        VStack(alignment: .leading, spacing: 8) {
            if query.isEmpty && !recents.isEmpty {
                Text("Frequently Used")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                grid(recents, label: { Self.emojiNames[$0] ?? $0 }) { Text($0).font(.title3) }
            }
            if query.isEmpty {
                Text("All Emoji")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            grid(Self.emoji.filter { query.isEmpty || $0.name.contains(query) }.map(\.symbol),
                 label: { Self.emojiNames[$0] ?? $0 }) {
                Text($0).font(.title3)
            }
        }
    }

    private func grid<Content: View>(_ items: [String], label: @escaping (String) -> String,
                                     @ViewBuilder content: @escaping (String) -> Content) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 32))], spacing: 4) {
            ForEach(items, id: \.self) { item in
                Button {
                    choose(item)
                } label: {
                    content(item)
                        .frame(width: 28, height: 28)
                        .background(icon.wrappedValue == item ? Color.accentColor.opacity(0.25) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(label(item))
            }
        }
    }

    private func choose(_ icon: String?) {
        if let icon, state.iconTab == .emoji {
            let recents = (UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []).filter { $0 != icon }
            UserDefaults.standard.set(Array(([icon] + recents).prefix(16)), forKey: Self.recentsKey)
        }
        self.icon.wrappedValue = icon
        dismiss()
    }
}
