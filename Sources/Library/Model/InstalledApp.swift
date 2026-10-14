import SwiftUI

/// The app's display name without the `.app` suffix.
func appName(at path: String) -> String {
    FileManager.default.displayName(atPath: path)
        .replacingOccurrences(of: ".app", with: "", options: [.anchored, .backwards])
}

struct InstalledApp: Identifiable {
    let name: String
    let path: String
    var id: String { path }

    /// Finds `.app` bundles in the standard application folders, one subfolder deep.
    static func scan() -> [InstalledApp] {
        let fm = FileManager.default
        let roots = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        var found: [String: InstalledApp] = [:]

        func visit(_ dir: String, depth: Int) {
            for entry in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where !entry.hasPrefix(".") {
                let path = dir + "/" + entry
                if entry.hasSuffix(".app") {
                    found[path] = InstalledApp(name: appName(at: path), path: path)
                } else if depth < 1 {
                    visit(path, depth: depth + 1)
                }
            }
        }

        roots.forEach { visit($0, depth: 0) }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
