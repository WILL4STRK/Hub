import CoreGraphics
import Foundation

/// Where to drop a ⌘-dragged item so it lands in a section. All frames are in
/// Core Graphics coordinates (top-left origin), the space CGEvent uses.
/// Expects revealed dividers (state `.showAll`), so both are on screen.
/// Sections run right to left: visible (right of the chevron), hidden,
/// always-hidden. A dragged item lands on the far side of every midpoint it crosses.
public enum DropPlan {
    public static func dropPoint(for section: MenuSection, toggle: CGRect, hiddenDivider: CGRect, alwaysHiddenDivider: CGRect?) -> CGPoint? {
        let y = hiddenDivider.midY
        switch section {
        case .visible:
            // Just past the chevron's right edge: crosses the chevron's midpoint
            // but not the next item's, so it lands right of the chevron.
            return CGPoint(x: toggle.maxX + 4, y: y)
        case .hidden:
            // Left part of the hidden divider: lands just left of it.
            return CGPoint(x: hiddenDivider.minX + 2, y: y)
        case .alwaysHidden:
            guard let always = alwaysHiddenDivider else { return nil }
            return CGPoint(x: always.minX + 2, y: y)
        }
    }
}

/// Stable-ish identity for another app's status item: owner bundle ID (or
/// name) plus its left-to-right index among that owner's items.
public enum ItemKey {
    public static func keys(owners: [String], minXs: [CGFloat]) -> [String] {
        precondition(owners.count == minXs.count)
        let order = minXs.indices.sorted { minXs[$0] < minXs[$1] }
        var seen: [String: Int] = [:]
        var result = Array(repeating: "", count: owners.count)
        for i in order {
            let n = seen[owners[i], default: 0]
            seen[owners[i]] = n + 1
            result[i] = "\(owners[i])#\(n)"
        }
        return result
    }
}

/// ⌘-drag by posting CGEvents. The posting process must be trusted for
/// Accessibility, or macOS drops the events silently. Moves the pointer.
public enum CommandDrag {
    public static func perform(from start: CGPoint, to end: CGPoint, steps: Int = 24) {
        let source = CGEventSource(stateID: .hidSystemState)
        let commandKey: CGKeyCode = 0x37
        let restore = CGEvent(source: nil)?.location

        func mouse(_ type: CGEventType, _ point: CGPoint, command: Bool = true) {
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            event?.flags = command ? .maskCommand : []
            event?.post(tap: .cghidEventTap)
        }
        func key(down: Bool) {
            let event = CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: down)
            event?.flags = down ? .maskCommand : []
            event?.post(tap: .cghidEventTap)
        }

        key(down: true)
        usleep(30_000)
        mouse(.mouseMoved, start)
        usleep(60_000)
        mouse(.leftMouseDown, start)
        usleep(200_000)
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            mouse(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
            usleep(20_000)
        }
        usleep(200_000)
        mouse(.leftMouseUp, end)
        usleep(100_000)
        key(down: false)
        usleep(300_000)
        if let restore { mouse(.mouseMoved, restore, command: false) }
    }
}

/// Commands Shelf accepts over a local distributed notification
/// (used by the self-test). Payload is the notification object string.
public enum ShelfCommand: String, CaseIterable {
    case collapse, showHidden, showAll
    public static let notificationName = "local.shelf.command"
    /// "pickWindow:<CGWindowID>" opens that item as a search pick would.
    public static let pickWindowPrefix = "pickWindow:"
}
