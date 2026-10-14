import SwiftUI

/// The shortcut control from System Settings: click it, then press the shortcut. The field shows an accent
/// outline while it listens. Escape or a click elsewhere cancels. The menu sets a hot corner or clears it.
struct ShortcutField: View {
    @Binding var shortcut: Shortcut?
    let isRecording: Bool
    let setRecording: (Bool) -> Void
    var clearable = true

    private var isSet: Bool { shortcut.map { !$0.isEmpty } ?? false }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                setRecording(true)
            } label: {
                Text(isRecording ? "Press a shortcut…" : isSet ? shortcut!.description : "Record Shortcut")
                    .foregroundStyle(isSet && !isRecording ? Color.primary : Color.secondary)
                    .frame(minWidth: 150)
            }
            .overlay {
                if isRecording {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            Menu {
                Menu("Hot Corner") {
                    ForEach(Shortcut.corners, id: \.self) { corner in
                        Button(Shortcut.gestureNames[corner] ?? corner) {
                            set(Shortcut(modifiers: 0, gesture: corner))
                        }
                    }
                }
                if clearable {
                    Divider()
                    Button("Clear") { shortcut = nil }
                        .disabled(!isSet)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("More shortcut options")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Hot corner and clear")
        }
        .background {
            if isRecording {
                ShortcutRecorder(onRecord: { recorded in
                    set(recorded)
                    setRecording(false)
                    if (recorded.button != nil || recorded.gesture != nil) && !recorded.isCorner && !HotKeys.hasClickAccess {
                        HotKeys.requestClickAccess()
                    }
                }, onCancel: { setRecording(false) })
            }
        }
    }

    /// Replaces the trigger and keeps the item's open behavior.
    private func set(_ new: Shortcut) {
        var new = new
        new.openNew = shortcut?.openNew ?? false
        shortcut = new
    }
}
