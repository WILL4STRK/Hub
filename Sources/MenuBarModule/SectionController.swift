import AppKit
import ShelfCore

/// Owns the three Shelf status items. Creation order sets the initial order
/// (newer items appear to the left): toggle, then hidden divider, then
/// always-hidden divider. autosaveName keeps positions after the user ⌘-drags them.
final class SectionController {
    let toggleItem: NSStatusItem
    let hiddenDivider: NSStatusItem
    let alwaysHiddenDivider: NSStatusItem
    private(set) var state: ShelfState = .collapsed

    init(target: AnyObject, action: Selector) {
        let bar = NSStatusBar.system
        toggleItem = bar.statusItem(withLength: NSStatusItem.squareLength)
        toggleItem.autosaveName = "ShelfToggle"
        hiddenDivider = bar.statusItem(withLength: SectionLayout.expandedLength)
        hiddenDivider.autosaveName = "ShelfHiddenDivider"
        alwaysHiddenDivider = bar.statusItem(withLength: SectionLayout.expandedLength)
        alwaysHiddenDivider.autosaveName = "ShelfAlwaysHiddenDivider"

        if let button = toggleItem.button {
            button.target = target
            button.action = action
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityHelp("Click to show or hide menu bar items. Option-click shows every section.")
        }
        // Dividers are disabled so a collapsed (very wide) divider never
        // highlights across the menu bar. ⌘-drag still moves them.
        for (item, label) in [(hiddenDivider, "Shelf hidden section divider"),
                              (alwaysHiddenDivider, "Shelf always-hidden section divider")] {
            item.button?.isEnabled = false
            item.button?.setAccessibilityLabel(label)
        }
    }

    func apply(_ newState: ShelfState, alwaysHiddenEnabled: Bool) {
        let effective: ShelfState = (newState == .showAll && !alwaysHiddenEnabled) ? .showHidden : newState
        state = effective
        let lengths = SectionLayout.lengths(for: effective)

        hiddenDivider.length = lengths.hidden
        hiddenDivider.button?.image = lengths.hidden == SectionLayout.expandedLength ? nil : Self.dividerImage(dashed: false)

        alwaysHiddenDivider.isVisible = alwaysHiddenEnabled
        alwaysHiddenDivider.length = lengths.alwaysHidden
        alwaysHiddenDivider.button?.image = lengths.alwaysHidden == SectionLayout.expandedLength ? nil : Self.dividerImage(dashed: true)

        updateToggleImage()
    }

    private func updateToggleImage() {
        guard let button = toggleItem.button else { return }
        let collapsed = state == .collapsed
        let label = collapsed ? "Show hidden menu bar items" : "Hide menu bar items"
        button.image = NSImage(systemSymbolName: collapsed ? "chevron.left" : "chevron.right",
                               accessibilityDescription: label)
        button.setAccessibilityLabel(label)
    }

    /// Takes all three items out of the menu bar (Menu Bar module switched off). Positions stay saved.
    func remove() {
        for item in [toggleItem, hiddenDivider, alwaysHiddenDivider] { NSStatusBar.system.removeStatusItem(item) }
    }

    /// Frames in Cocoa screen coordinates.
    var toggleFrame: CGRect? { toggleItem.button?.window?.frame }
    var hiddenDividerFrame: CGRect? { hiddenDivider.button?.window?.frame }
    var alwaysHiddenDividerFrame: CGRect? {
        alwaysHiddenDivider.isVisible ? alwaysHiddenDivider.button?.window?.frame : nil
    }

    /// The screen showing Shelf's toggle (the menu bar it lives in).
    var screen: NSScreen? { toggleItem.button?.window?.screen ?? NSScreen.main }

    private static func dividerImage(dashed: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 2, height: 14), flipped: false) { rect in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.midX, y: rect.minY + 1))
            path.line(to: NSPoint(x: rect.midX, y: rect.maxY - 1))
            path.lineWidth = 1
            if dashed { path.setLineDash([2, 2], count: 2, phase: 0) }
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
