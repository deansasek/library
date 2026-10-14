import SwiftUI

/// Gives the window it sits in an autosave name, so AppKit restores its size and position on the next launch
/// and saves them as the window moves.
struct WindowFrameAutosave: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> AutosaveView {
        AutosaveView(name: name)
    }

    func updateNSView(_ nsView: AutosaveView, context: Context) {}

    final class AutosaveView: NSView {
        private let name: String

        init(name: String) {
            self.name = name
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            _ = window?.setFrameAutosaveName(name)
        }
    }
}
