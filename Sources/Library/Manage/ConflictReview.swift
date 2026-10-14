import SwiftUI

/// The Review step of an iCloud conflict: one row per item that differs, with the version to keep. It runs modally,
/// because a conflict can arrive when no window is open. Cancel returns to the first choice.
@MainActor
enum ConflictReview {
    /// The side picked for each item that differs, or nil when the user cancels.
    static func run(_ differences: [LibrarySync.Difference]) -> [UUID: LibrarySync.Side]? {
        let model = ConflictReviewModel(differences: differences)
        let window = NSWindow(contentViewController: NSHostingController(rootView: ConflictReviewView(model: model)))
        window.title = "Review Changes"
        window.styleMask = [.titled]
        window.isReleasedWhenClosed = false
        window.center()
        model.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: window)
        window.orderOut(nil)
        return model.result
    }
}

@MainActor
final class ConflictReviewModel: ObservableObject {
    let differences: [LibrarySync.Difference]
    @Published var choices: [UUID: LibrarySync.Side] = [:]
    var result: [UUID: LibrarySync.Side]?
    weak var window: NSWindow?

    init(differences: [LibrarySync.Difference]) {
        self.differences = differences
    }

    func finish(keeping choices: [UUID: LibrarySync.Side]?) {
        result = choices
        NSApp.stopModal()
    }
}

struct ConflictReviewView: View {
    @ObservedObject var model: ConflictReviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose the version of each item to keep. Items that match in both versions are not listed.")
                .foregroundStyle(.secondary)
            if model.differences.isEmpty {
                Text("No items differ.")
            } else {
                List(model.differences) { difference in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(difference.name.isEmpty ? "Untitled" : difference.name)
                            Text("This Mac: \(difference.thisMac)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Other version: \(difference.other)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Picker("Keep", selection: Binding(
                            get: { model.choices[difference.id] ?? .thisMac },
                            set: { model.choices[difference.id] = $0 }
                        )) {
                            Text("This Mac").tag(LibrarySync.Side.thisMac)
                            Text("Other Version").tag(LibrarySync.Side.other)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 200)
                    }
                }
                .frame(minHeight: 260)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.finish(keeping: nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Done") {
                    var picks: [UUID: LibrarySync.Side] = [:]
                    for difference in model.differences {
                        picks[difference.id] = model.choices[difference.id] ?? .thisMac
                    }
                    model.finish(keeping: picks)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
