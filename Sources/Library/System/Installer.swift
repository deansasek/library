import SwiftUI

/// Moves the app into the Applications folder, the way Mac apps are installed.
enum Installer {
    /// True when the app already sits in /Applications or ~/Applications.
    static var isInApplications: Bool {
        let folder = Bundle.main.bundleURL.deletingLastPathComponent().standardizedFileURL.path
        return folder == "/Applications" || folder == NSHomeDirectory() + "/Applications"
    }

    /// Copies the app to /Applications, replacing an older copy, puts the older copy in the Trash, quits this app,
    /// and opens the new copy. The new copy is made beside the old one first, so a failed copy leaves the older copy
    /// where it was. An error is shown to the user.
    @MainActor
    @discardableResult
    static func moveToApplications() -> Bool {
        let fm = FileManager.default
        let destination = URL(fileURLWithPath: "/Applications/\(Bundle.main.bundleURL.lastPathComponent)")
        let staging = URL(fileURLWithPath: "/Applications/.Library-\(UUID().uuidString).installing")
        let previous = URL(fileURLWithPath: "/Applications/.Library-\(UUID().uuidString).previous")
        let replacing = fm.fileExists(atPath: destination.path)
        // Only an older copy of this app is replaced. Another app that happens to have the same file name is left alone.
        if replacing, Bundle(url: destination)?.bundleIdentifier != Bundle.main.bundleIdentifier {
            showFailure(String(localized: "Applications already has a different app named Library.app. Move it out of the way yourself, then try again. Nothing was changed.", bundle: L10n.bundle))
            return false
        }
        do {
            try fm.copyItem(at: Bundle.main.bundleURL, to: staging)
        } catch {
            try? fm.removeItem(at: staging)
            showFailure(errorDetail(error))
            return false
        }
        // Moving the older copy aside and the new copy into place are renames on the same volume. If the second
        // fails, the older copy goes back, and only then is the older copy trashed.
        do {
            if replacing {
                try fm.moveItem(at: destination, to: previous)
            }
            do {
                try fm.moveItem(at: staging, to: destination)
            } catch {
                if replacing {
                    try? fm.moveItem(at: previous, to: destination)
                }
                throw error
            }
        } catch {
            try? fm.removeItem(at: staging)
            showFailure(errorDetail(error))
            return false
        }
        if replacing {
            try? fm.trashItem(at: previous, resultingItemURL: nil)
        }
        // The new copy opens the tour on its last page, so the green check closes the loop.
        UserDefaults.standard.set(true, forKey: "resumeWelcomeAfterMove")
        // The login item remembers the app's old location, so the new copy turns it on again.
        if LoginItem.shared.isEnabled {
            UserDefaults.standard.set(true, forKey: "reenableLoginItemAfterMove")
            LoginItem.shared.set(false)
        }
        // Opening the new copy while this one runs would just bring this one forward, and a copy that is in the
        // Trash cannot open at all. So a helper process waits a moment, until this app has quit, and opens the
        // new copy as a fresh launch.
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 0.6; /usr/bin/open -n \"$0\"", destination.path]
        try? relaunch.run()
        try? fm.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil)
        NSApp.terminate(nil)
        return true
    }

    /// The detail for a failed move: the error, and a note that the app can be dragged into Applications by hand.
    private static func errorDetail(_ error: Error) -> String {
        "\(error.localizedDescription)\n\n" + String(localized: "You can drag Library.app into your Applications folder yourself.", bundle: L10n.bundle)
    }

    /// Tells the user the move did not happen, with the reason.
    @MainActor
    private static func showFailure(_ detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Library Couldn’t Be Moved", bundle: L10n.bundle)
        alert.informativeText = detail
        alert.runModal()
    }
}
