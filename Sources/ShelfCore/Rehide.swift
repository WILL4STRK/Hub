import Foundation

public enum RehidePolicy {
    public static let minSeconds: Double = 1
    public static let maxSeconds: Double = 60

    public static func clamp(_ seconds: Double) -> Double {
        min(max(seconds, minSeconds), maxSeconds)
    }

    public enum Decision: Equatable {
        case rehide
        /// Try again after this many seconds.
        case wait(TimeInterval)
    }

    /// When the timer fires, do not yank items away while the pointer is in
    /// the menu bar or a menu opened from a revealed item is still on screen.
    public static func decide(pointerInMenuBar: Bool, menuOpen: Bool) -> Decision {
        (pointerInMenuBar || menuOpen) ? .wait(2) : .rehide
    }
}
