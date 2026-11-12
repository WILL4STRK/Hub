import AppKit
import CoreGraphics

/// Turns lock, sleep and fast-user-switch notifications into one suspend/resume signal.
/// Event driven: no timers.
final class SessionWatcher {
    private var gate = SessionGate()
    private let onChange: (SessionGate.Change) -> Void
    private var tokens: [NSObjectProtocol] = []

    init(onChange: @escaping (SessionGate.Change) -> Void) {
        self.onChange = onChange
        let dnc = DistributedNotificationCenter.default()
        observe(dnc, "com.apple.screenIsLocked", .screenLocked)
        observe(dnc, "com.apple.screenIsUnlocked", .screenUnlocked)

        let ws = NSWorkspace.shared.notificationCenter
        observe(ws, NSWorkspace.screensDidSleepNotification, .screensSlept)
        observe(ws, NSWorkspace.screensDidWakeNotification, .screensWoke)
        observe(ws, NSWorkspace.willSleepNotification, .systemWillSleep)
        observe(ws, NSWorkspace.didWakeNotification, .systemDidWake)
        observe(ws, NSWorkspace.sessionDidResignActiveNotification, .sessionResigned)
        observe(ws, NSWorkspace.sessionDidBecomeActiveNotification, .sessionActivated)
    }

    deinit {
        for t in tokens {
            DistributedNotificationCenter.default().removeObserver(t)
            NSWorkspace.shared.notificationCenter.removeObserver(t)
        }
    }

    private func observe(_ center: NotificationCenter, _ name: String, _ event: SessionGate.Event) {
        observe(center, NSNotification.Name(name), event)
    }

    private func observe(_ center: NotificationCenter, _ name: NSNotification.Name, _ event: SessionGate.Event) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            self?.handle(event)
        }
        tokens.append(token)
    }

    private func handle(_ event: SessionGate.Event) {
        NSLog("Awning session: %@", String(describing: event))
        if let change = gate.handle(event) { onChange(change) }
        // A missed unlock notification must not keep the island hidden forever.
        switch event {
        case .screensWoke, .systemDidWake, .sessionActivated:
            if let change = gate.reconcile(lockedNow: Self.screenIsLocked()) { onChange(change) }
        default:
            break
        }
    }

    /// Real lock state of this login session.
    static func screenIsLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}
