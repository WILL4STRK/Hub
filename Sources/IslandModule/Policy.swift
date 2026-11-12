import Foundation

// Pure logic shared by the app and the checks in scripts/Checks (Foundation only, no UI).

enum IslandState {
    case collapsed, hovered, expanded

    /// Size order: collapsed < hovered < expanded.
    var rank: Int {
        switch self {
        case .collapsed: return 0
        case .hovered: return 1
        case .expanded: return 2
        }
    }
}

/// Animation timing. Things that open animate briefly; things that close are instant.
enum MotionPolicy {
    /// Opening transitions: island grow, toast in, output list, onboarding page, glow in.
    static let openDuration: TimeInterval = 0.18
    /// Small feedback: button press, level meter, battery sweep, lyrics line.
    static let feedbackDuration: TimeInterval = 0.15

    /// Seconds an island state change animates. 0 means instant.
    static func duration(from old: IslandState, to new: IslandState, reduceMotion: Bool) -> TimeInterval {
        guard !reduceMotion, new.rank > old.rank else { return 0 }
        return openDuration
    }

    /// Seconds a show/hide of a single element animates (toast, wings, glow, output list).
    static func duration(showing: Bool, reduceMotion: Bool) -> TimeInterval {
        showing && !reduceMotion ? openDuration : 0
    }

    /// Seconds a continuous value change animates (meters, press feedback).
    static func feedback(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0 : feedbackDuration
    }
}

/// Tracks screen lock, sleep and fast user switching. Awning's island, toasts and popovers
/// stay hidden while any of them is in effect.
struct SessionGate {
    enum Event {
        case screenLocked, screenUnlocked
        case screensSlept, screensWoke
        case systemWillSleep, systemDidWake
        case sessionResigned, sessionActivated
    }

    enum Change: Equatable { case suspend, resume }

    private(set) var locked = false
    private(set) var screensAsleep = false
    private(set) var systemAsleep = false
    private(set) var switchedOut = false

    var isSuspended: Bool { locked || screensAsleep || systemAsleep || switchedOut }

    /// Applies an event. Returns .suspend or .resume only when isSuspended flips.
    mutating func handle(_ event: Event) -> Change? {
        let before = isSuspended
        switch event {
        case .screenLocked: locked = true
        case .screenUnlocked: locked = false
        case .screensSlept: screensAsleep = true
        case .screensWoke: screensAsleep = false
        case .systemWillSleep: systemAsleep = true
        case .systemDidWake: systemAsleep = false
        case .sessionResigned: switchedOut = true
        case .sessionActivated: switchedOut = false
        }
        return change(from: before)
    }

    /// Clears the lock flag when the real session state says unlocked, in case an unlock
    /// notification was missed. Never sets it: only com.apple.screenIsLocked does that,
    /// so a stale "locked" reading cannot hide the island after a real unlock.
    mutating func reconcile(lockedNow: Bool) -> Change? {
        let before = isSuspended
        if !lockedNow { locked = false }
        return change(from: before)
    }

    private func change(from before: Bool) -> Change? {
        switch (before, isSuspended) {
        case (false, true): return .suspend
        case (true, false): return .resume
        default: return nil
        }
    }
}
