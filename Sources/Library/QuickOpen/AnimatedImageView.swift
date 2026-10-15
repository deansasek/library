import SwiftUI

/// Shows an image and plays it if it is animated, as a SwiftUI Image does not. With Reduce Motion on, it shows the
/// first frame and does not play.
struct AnimatedImageView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.setAccessibilityLabel(String(localized: "Copied image", bundle: L10n.bundle))
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        if view.image !== image { view.image = image }
        // Read on every update, so the image stops or starts when the setting changes.
        view.animates = !context.environment.accessibilityReduceMotion
    }
}
