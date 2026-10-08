import Foundation
import ServiceManagement

@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ on: Bool) {
        do {
            if on {
                if SMAppService.mainApp.status == .enabled { return }
                try SMAppService.mainApp.register()
            } else {
                if SMAppService.mainApp.status != .enabled { return }
                try SMAppService.mainApp.unregister()
            }
            Prefs.launchAtLogin = on
        } catch {
            // Common when running an ad-hoc-signed build outside /Applications;
            // the menu checkbox will just reflect reality next time it's opened.
        }
    }

    /// Called once at launch so a user's stored preference is honoured even if
    /// the app was reinstalled or macOS reset the registration.
    static func syncToStoredPreference() {
        guard Prefs.launchAtLoginPreferenceSet else { return }
        set(Prefs.launchAtLogin)
    }
}
