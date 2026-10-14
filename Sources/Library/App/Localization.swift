import Foundation

/// The bundle that holds the app's translated strings. SwiftPM puts the Resources folder into
/// `Library_Library.bundle`, and build.sh copies that bundle into the app's Contents/Resources.
/// Localized strings must name this bundle, because the app's main bundle does not hold them.
/// Falls back to the main bundle when the resource bundle is missing, as in test.sh's direct compile.
enum L10n {
    static let bundle: Bundle = {
        let name = "Library_Library.bundle"
        for base in [Bundle.main.resourceURL, Bundle.main.bundleURL].compactMap({ $0 }) {
            if let found = Bundle(url: base.appendingPathComponent(name)) {
                return found
            }
        }
        return .main
    }()
}
