import AppKit
import SwiftUI

/// SwiftUI side of MotionPolicy. Reads Reduce Motion live, so a change in
/// System Settings applies to the next transition without a relaunch.
enum Motion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Ease-out curve for `seconds`, or nil (instant) when seconds is 0.
    static func curve(_ seconds: TimeInterval) -> Animation? {
        seconds > 0 ? .easeOut(duration: seconds) : nil
    }

    /// Implicit animation for an element that is appearing (nil when hiding: hiding is instant).
    static func show(_ showing: Bool) -> Animation? {
        curve(MotionPolicy.duration(showing: showing, reduceMotion: reduced))
    }

    /// Implicit animation for small value changes (meters, press feedback).
    static var feedback: Animation? { curve(MotionPolicy.feedback(reduceMotion: reduced)) }

    /// Runs `body` with `seconds` of animation, or with every animation disabled when 0,
    /// so closing views, glows and shadows disappear in the same frame.
    static func perform(_ seconds: TimeInterval, _ body: () -> Void) {
        if let animation = curve(seconds) {
            withAnimation(animation, body)
        } else {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t, body)
        }
    }

    /// Animates an element that is appearing; applies a hide instantly.
    static func perform(showing: Bool, _ body: () -> Void) {
        perform(MotionPolicy.duration(showing: showing, reduceMotion: reduced), body)
    }
}
