import AppKit
import HubCore
import Island
import MenuBar
import Widgets

/// Owns the three modules: their on/off switches, and pausing while an old app that clashes is running.
@MainActor
final class ModuleManager: ObservableObject {
    @Published private(set) var enabled: [HubModuleID: Bool] = [:]
    /// Bundle ids of the old apps that are running now.
    @Published private(set) var runningOldApps: Set<String> = []
    /// Bumped every 2 s while Settings is open, so status lines refresh. Nothing ticks otherwise.
    @Published private(set) var tick = 0

    private var observers: [Any] = []
    private var ticker: Timer?

    init() {
        let d = UserDefaults.standard
        for id in HubModuleID.allCases {
            d.register(defaults: [id.enabledKey: true])
            enabled[id] = d.bool(forKey: id.enabledKey)
        }
        refreshRunning()
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let id = app?.bundleIdentifier,
                      HubModuleID.allCases.contains(where: { $0.blockingBundleIDs.contains(id) }) else { return }
                // At didTerminate time runningApplications can still list the app that just quit: skip its pid.
                let gone = note.name == NSWorkspace.didTerminateApplicationNotification ? app?.processIdentifier : nil
                MainActor.assumeIsolated {
                    self?.refreshRunning(excluding: gone)
                    self?.apply()
                }
            })
        }
    }

    private func refreshRunning(excluding gone: pid_t? = nil) {
        let all = Set(HubModuleID.allCases.flatMap(\.blockingBundleIDs))
        let now = Set(NSWorkspace.shared.runningApplications
            .filter { !$0.isTerminated && $0.processIdentifier != gone }
            .compactMap(\.bundleIdentifier).filter(all.contains))
        if now != runningOldApps { runningOldApps = now }
    }

    func isEnabled(_ id: HubModuleID) -> Bool { enabled[id] ?? true }

    func setEnabled(_ id: HubModuleID, _ on: Bool) {
        enabled[id] = on
        UserDefaults.standard.set(on, forKey: id.enabledKey)
        apply()
    }

    func blockers(_ id: HubModuleID) -> [String] { id.blockers(running: runningOldApps) }

    /// Running right now: switched on and not paused by an old app.
    func isActive(_ id: HubModuleID) -> Bool { isEnabled(id) && blockers(id).isEmpty }

    /// Starts or stops each module to match its switch and the old apps.
    func apply() {
        for id in HubModuleID.allCases {
            let on = isActive(id)
            switch id {
            case .widgets: on ? WidgetsModule.shared.start() : WidgetsModule.shared.stop()
            case .island: on ? IslandModule.shared.start() : IslandModule.shared.stop()
            case .menuBar: on ? MenuBarModule.shared.start() : MenuBarModule.shared.stop()
            }
        }
        objectWillChange.send()
    }

    func statusText(_ id: HubModuleID) -> String {
        if !isEnabled(id) { return "Off" }
        let b = blockers(id)
        if !b.isEmpty {
            return "Paused while \(b.joined(separator: " and ")) \(b.count == 1 ? "is" : "are") running. Quit \(b.count == 1 ? "it" : "them") to switch over."
        }
        switch id {
        case .widgets: return WidgetsModule.shared.statusText
        case .island: return IslandModule.shared.statusText
        case .menuBar: return MenuBarModule.shared.statusText
        }
    }

    /// Quit everything: every module stops (the menu bar is collapsed first), then Hub quits.
    func stopAll() {
        MenuBarModule.shared.prepareForQuit()
        WidgetsModule.shared.stop()
        IslandModule.shared.stop()
        MenuBarModule.shared.stop()
    }

    func startTicking() {
        guard ticker == nil else { return }
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick &+= 1 }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }
}
