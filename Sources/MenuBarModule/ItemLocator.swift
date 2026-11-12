import AppKit
import ShelfCore
import SwiftUI

/// A brief accent-colored outline drawn over a real menu bar item.
/// Click-through, above the menu bar, never takes focus.
final class ItemLocator {
    private var window: NSWindow?
    private var hideWork: DispatchWorkItem?

    func show(at frame: CGRect, for seconds: TimeInterval = 1.5) {
        hide()
        let rect = frame.insetBy(dx: -2, dy: -1)
        let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        window.contentView = NSHostingView(rootView: LocatorShape())
        window.setAccessibilityElement(false)

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        window.alphaValue = reduceMotion ? 1 : 0
        window.orderFrontRegardless()
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.15; window.animator().alphaValue = 1 }
        }
        self.window = window

        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        window?.orderOut(nil)
        window = nil
    }
}

private struct LocatorShape: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color.accentColor.opacity(0.25))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor, lineWidth: 2))
    }
}

extension ShelfController {
    /// Hovering a Settings row: after a short dwell, outline the item. A hidden
    /// item's section is revealed for the hover and restored afterwards.
    /// `key == nil` ends the hover.
    func locate(_ key: String?) {
        locateWork?.cancel()
        guard let key else {
            locator.hide()
            if let restore = locateRestoreState {
                locateRestoreState = nil
                restoreAfterArranging(restore)
            }
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.performLocate(key) }
        locateWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func performLocate(_ key: String) {
        guard let entry = MenuBarItems.describe().first(where: { $0.key == key }) else { return }
        let section = currentSection(of: entry.item)
        let needed: ShelfState? = {
            switch section {
            case .visible: return nil
            case .hidden: return currentState == .collapsed ? .showHidden : nil
            case .alwaysHidden: return currentState == .showAll ? nil : .showAll
            }
        }()
        Log.arrange.info("locate \(key, privacy: .public): section=\(section.rawValue, privacy: .public) reveal=\(needed?.rawValue ?? "none", privacy: .public)")
        guard let needed else {
            locator.show(at: entry.item.frame)
            return
        }
        if locateRestoreState == nil { locateRestoreState = currentState }
        revealForLocate(needed)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.locateRestoreState != nil,
                  let fresh = MenuBarItems.describe().first(where: { $0.key == key }) else { return }
            self.locator.show(at: fresh.item.frame)
        }
    }
}
