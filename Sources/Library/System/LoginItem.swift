import ServiceManagement
import SwiftUI

/// What the Open at Login toggles show.
enum LoginItemPresentation: Equatable {
    case on
    case off
    /// Registered, but the person has not allowed it in System Settings > Login Items yet.
    case needsApproval
}

/// The Open at Login setting. The status is read from the system each time it is read, not kept from launch, so a
/// change made in System Settings shows up, and the views refresh when Library becomes active again.
@MainActor
final class LoginItem: ObservableObject {
    static let shared = LoginItem()

    private init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }
    }

    var presentation: LoginItemPresentation { Self.presentation(for: SMAppService.mainApp.status) }

    var isEnabled: Bool { presentation == .on }

    var needsApproval: Bool { presentation == .needsApproval }

    /// Maps a system status to what the toggles show. A status that cannot register is shown as off.
    static func presentation(for status: SMAppService.Status) -> LoginItemPresentation {
        switch status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        default: return .off
        }
    }

    /// Opens System Settings at Login Items, where the person allows Library.
    static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Registers or unregisters Library. A failure is shown in an alert, so the toggle never snaps back silently.
    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Launch at login failed: \(error)")
            Self.reportFailure(error, enabling: enabled)
        }
        objectWillChange.send()
    }

    @MainActor
    private static func reportFailure(_ error: Error, enabling: Bool) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = enabling
            ? String(localized: "Library Can’t Open at Login", bundle: L10n.bundle)
            : String(localized: "Library Can’t Stop Opening at Login", bundle: L10n.bundle)
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: String(localized: "OK", bundle: L10n.bundle))
        alert.runModal()
    }
}

/// Shown under the Open at Login toggle while the person has to allow Library in System Settings.
struct LoginItemApprovalNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Allow Library in System Settings under Login Items to open it at login.", bundle: L10n.bundle)
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                LoginItem.openSettings()
            } label: {
                Text("Open Login Items…", bundle: L10n.bundle)
            }
        }
    }
}
