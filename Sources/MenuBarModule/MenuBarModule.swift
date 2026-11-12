import AppKit
import ApplicationServices
import ShelfCore
import SwiftUI

/// The Shelf module inside Hub: menu-bar sections, arranger, search, shortcuts, notch bar, tint.
/// Created on the first `start()`. `stop()` collapses the sections and removes Shelf's status items,
/// event monitors, shortcuts and tint; positions and choices stay saved.
public final class MenuBarModule {
    public static let shared = MenuBarModule()
    /// Set by Hub: opens Hub's Settings on the Menu Bar page.
    public var onOpenSettings: (() -> Void)?
    /// Set by Hub: "Quit Hub" in the chevron's menu.
    public var onQuit: (() -> Void)?

    private var controller: ShelfController?
    public private(set) var isRunning = false

    private init() {}

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        if let controller {
            controller.unpark()
            return
        }
        NSLog("Hub menu bar: Accessibility trusted: %@", AXIsProcessTrusted() ? "yes" : "no")
        let c = ShelfController(settings: .shared)
        c.openSettings = { [weak self] in self?.onOpenSettings?() }
        c.quitApp = { [weak self] in self?.onQuit?() }
        controller = c
    }

    /// Leaves the menu bar as the user found it (all sections collapsed, items removed).
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        controller?.park()
    }

    /// Before Hub quits: collapse so no item stays pushed off screen.
    public func prepareForQuit() {
        controller?.collapse()
    }

    public func openSearch() { controller?.openSearch() }

    public var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// One line for Hub's Overview.
    public var statusText: String {
        guard isRunning, let controller else { return "Off" }
        let saved = AppSettings.shared.itemSections
        let hidden = saved.values.filter { $0 != .visible }.count
        let state = controller.isShowing ? "showing hidden items" : "collapsed"
        return "\(state) · \(hidden) item\(hidden == 1 ? "" : "s") hidden · Accessibility \(accessibilityTrusted ? "on" : "off")"
    }

    /// The Menu Bar page of Hub's Settings.
    public func settingsPage() -> AnyView {
        guard let controller else {
            return AnyView(Text("Turn the Menu Bar module on to change its settings.").foregroundColor(.secondary).padding(40))
        }
        return AnyView(SettingsView(
            settings: .shared, items: controller.itemList,
            onAssign: { [weak controller] key, section in controller?.assign(key, to: section) },
            onRefresh: { [weak controller] in controller?.refreshItemList() },
            onLocate: { [weak controller] key in controller?.locate(key) }))
    }
}
