import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp` for register/unregister of the launch-at-login state.
/// Requires macOS 13+. The app will be re-launched automatically by `launchd` after
/// the user signs in.
enum LoginItem {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    static func set(enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
        } catch {
            NSLog("VoicePTT: LoginItem set(\(enabled)) failed: \(error)")
        }
    }

    /// Reconcile the persisted user setting with the actual SMAppService state.
    /// Called once at app start so manual changes via System Settings → Login Items
    /// don't leave us out of sync.
    static func sync(with desired: Bool) {
        guard #available(macOS 13.0, *) else { return }
        let actual = SMAppService.mainApp.status == .enabled
        if actual != desired {
            set(enabled: desired)
        }
    }
}
