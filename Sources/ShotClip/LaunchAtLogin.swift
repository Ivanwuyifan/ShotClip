import ServiceManagement
import AppKit

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("ShotClip: LaunchAtLogin \(enabled ? "register" : "unregister") failed: \(error)")
        }
    }

    static func toggle() {
        set(!isEnabled)
    }

    private static let didAutoEnableKey = "ShotClip.didAutoEnableLoginItem"

    static func enableOnFirstRun() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didAutoEnableKey) else { return }
        defaults.set(true, forKey: didAutoEnableKey)
        set(true)
    }
}
