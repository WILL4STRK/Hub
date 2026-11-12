import CoreGraphics
import Foundation

/// Blocks every collapse or section change while Hub arranges menu-bar items.
/// A move holds the lock from before its synthetic mouse-down until mouse-up plus `settle`; the whole
/// arranging session (all moves, their checks and retries) holds it too. Without it, the rehide timer,
/// restore-after-arranging, leave-menu-bar rehide or a hover reveal could collapse the sections mid-drag,
/// and the item ended up unmoved.
public struct ArrangeLock: Equatable {
    public static let settle: TimeInterval = 0.8

    public private(set) var sessionActive = false
    public private(set) var dragging = false
    public private(set) var settleUntil: Date?

    public init() {}

    public mutating func beginSession() { sessionActive = true }
    public mutating func endSession() { sessionActive = false }
    /// Call before the synthetic mouse-down.
    public mutating func beginDrag() { dragging = true }
    /// Call right after the synthetic mouse-up.
    public mutating func endDrag(at now: Date) {
        dragging = false
        settleUntil = now.addingTimeInterval(Self.settle)
    }

    /// True while nothing may collapse or change the sections.
    public func blocks(at now: Date) -> Bool {
        if sessionActive || dragging { return true }
        if let settleUntil, now < settleUntil { return true }
        return false
    }
}

public enum MoveCheck {
    /// An item can be grabbed only when it lies fully on one screen (x between that screen's left and right
    /// edges). A frame read while its section was collapsed sits far off screen (x about -3800).
    public static func isOnScreen(_ item: CGRect, screens: [CGRect]) -> Bool {
        screens.contains { item.minX >= $0.minX && item.maxX <= $0.maxX && item.width > 0 }
    }

    public enum Outcome: Equatable {
        case done
        case retry
        case failed
    }

    /// After a move: landed in the wanted section -> done. Otherwise retry once, then fail.
    public static func outcome(landed: Bool, attempt: Int, maxAttempts: Int = 2) -> Outcome {
        if landed { return .done }
        return attempt < maxAttempts ? .retry : .failed
    }
}
