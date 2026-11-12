import Foundation
import ServiceManagement

/// Hub's one launch-at-login switch (SMAppService, macOS 13+).
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }
    static var isEnabled: Bool { status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    static var statusText: String {
        switch status {
        case .enabled: return "Hub opens when you log in."
        case .requiresApproval: return "Approve Hub in System Settings › General › Login Items."
        case .notFound: return "Login item not found. Run Hub from ~/Applications/Hub.app."
        default: return "Hub does not open at login."
        }
    }

    /// Launch at login starts on: turned on once, on the first run. Later choices are kept.
    static func enableOnce() {
        let key = "hub.launchAtLoginApplied"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        do { try set(true) } catch { NSLog("Hub: could not enable launch at login: %@", error.localizedDescription) }
    }
}
