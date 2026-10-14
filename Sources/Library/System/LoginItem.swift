import ServiceManagement
import SwiftUI

@MainActor
final class LoginItem: ObservableObject {
    static let shared = LoginItem()

    @Published private(set) var isEnabled = SMAppService.mainApp.status == .enabled

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Launch at login failed: \(error)")
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
