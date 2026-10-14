import SwiftUI

/// Moves the app into the Applications folder, the way Mac apps are installed.
enum Installer {
    /// True when the app already sits in /Applications or ~/Applications.
    static var isInApplications: Bool {
        let folder = Bundle.main.bundleURL.deletingLastPathComponent().standardizedFileURL.path
        return folder == "/Applications" || folder == NSHomeDirectory() + "/Applications"
    }

    /// Copies the app to /Applications, replacing an older copy, puts the original in the Trash, quits this app,
    /// and opens the new copy. An error is shown to the user and nothing else changes.
    @MainActor
    @discardableResult
    static func moveToApplications() -> Bool {
        let fm = FileManager.default
        let destination = URL(fileURLWithPath: "/Applications/\(Bundle.main.bundleURL.lastPathComponent)")
        do {
            if fm.fileExists(atPath: destination.path) {
                try fm.trashItem(at: destination, resultingItemURL: nil)
            }
            try fm.copyItem(at: Bundle.main.bundleURL, to: destination)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Library Couldn’t Be Moved"
            alert.informativeText = "\(error.localizedDescription)\n\nYou can drag Library.app into your Applications folder yourself."
            alert.runModal()
            return false
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
}
