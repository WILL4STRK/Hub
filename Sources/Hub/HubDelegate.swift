import AppKit
import HubCore
import Island
import MenuBar
import SwiftUI
import Widgets

@MainActor
final class HubDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var modules: ModuleManager!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private let router = SettingsRouter()
    private var closeObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before any module reads its settings or creates a status item or window.
        SettingsMigration.runIfNeeded()
        SettingsMigration.repairHoverIfNeeded()
        LoginItem.enableOnce()

        modules = ModuleManager()
        WidgetsModule.shared.onOpenSettings = { [weak self] in self?.openSettings(.widgets) }
        IslandModule.shared.onOpenSettings = { [weak self] in self?.openSettings(.island) }
        MenuBarModule.shared.onOpenSettings = { [weak self] in self?.openSettings(.menuBar) }
        MenuBarModule.shared.onQuit = { [weak self] in self?.quitEverything() }

        // Hub's one menu-bar icon. Created before Shelf's items, so it sits right of the chevron.
        // Hub's icon is the way into Settings, so it must never land in Shelf's hidden section. Until the user
        // moves it, place it just right of the chevron (a smaller preferred position sits further right).
        let d = UserDefaults.standard
        let hubKey = "NSStatusItem Preferred Position HubIcon"
        if d.object(forKey: hubKey) == nil {
            let chevron = d.object(forKey: "NSStatusItem Preferred Position ShelfToggle") as? Double
            d.set(max(1, (chevron ?? 400) - 1), forKey: hubKey)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "HubIcon"
        statusItem.button?.image = Self.icon()
        statusItem.button?.toolTip = "Hub"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        modules.apply()

        // First launch: show everything once. Later launches (login) stay quiet.
        if !UserDefaults.standard.bool(forKey: "hub.settingsShownOnce") {
            UserDefaults.standard.set(true, forKey: "hub.settingsShownOnce")
            openSettings(.overview)
        }

        DistributedNotificationCenter.default().addObserver(
            forName: .init("local.hub.Hub.openSettings"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.openSettings(.overview) }
        }
    }

    /// Opening Hub again (Finder, Spotlight, `open`) shows the Settings window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings(.overview)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Leave the menu bar as the user found it.
        modules?.stopAll()
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item("Settings…", #selector(settingsFromMenu), key: ","))
        menu.addItem(.separator())
        for id in HubModuleID.allCases {
            let mi = item(id.title, #selector(toggleModule(_:)))
            mi.representedObject = id.rawValue
            mi.state = modules.isEnabled(id) ? .on : .off
            let blockers = modules.blockers(id)
            if modules.isEnabled(id), !blockers.isEmpty {
                mi.title = "\(id.title) (paused: \(blockers.joined(separator: ", ")) running)"
            }
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        let search = item("Search Menu Bar Items…", #selector(searchFromMenu))
        search.isEnabled = modules.isActive(.menuBar)
        menu.addItem(search)
        let refresh = item("Refresh Widgets", #selector(refreshWidgets))
        refresh.isEnabled = modules.isActive(.widgets)
        menu.addItem(refresh)
        menu.addItem(.separator())
        menu.addItem(item("Quit Everything", #selector(quitFromMenu), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        return mi
    }

    @objc private func settingsFromMenu() { openSettings(.overview) }
    @objc private func searchFromMenu() { MenuBarModule.shared.openSearch() }
    @objc private func refreshWidgets() { WidgetsModule.shared.refresh() }
    @objc private func quitFromMenu() { quitEverything() }
    @objc private func toggleModule(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = HubModuleID(rawValue: raw) else { return }
        modules.setEnabled(id, !modules.isEnabled(id))
    }

    /// Stops every module (menu bar collapsed, island and widgets off screen) and quits Hub.
    /// The three old apps are separate and are not touched.
    func quitEverything() {
        modules.stopAll()
        NSApp.terminate(nil)
    }

    // MARK: Settings window

    func openSettings(_ page: SettingsPage) {
        IslandModule.shared.collapse()
        router.page = page
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 640),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Hub"
            w.minSize = NSSize(width: 700, height: 480)
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: HubSettingsView(
                modules: modules, router: router, onQuit: { [weak self] in self?.quitEverything() }))
            w.setContentSize(NSSize(width: 820, height: 640))
            w.center()
            w.setFrameAutosaveName("HubSettings")
            settingsWindow = w
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.modules.stopTicking()
                    IslandModule.shared.settingsClosed()
                }
            }
        }
        modules.startTicking()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Template icon: four rounded tiles, one per part of Hub plus the hub itself.
    static func icon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: false) { rect in
            NSColor.black.setFill()
            NSColor.black.setStroke()
            let s: CGFloat = 6.5, g: CGFloat = 2
            let x0 = rect.midX - s - g / 2, y0 = rect.midY - s - g / 2
            for (i, j) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                let r = NSRect(x: x0 + CGFloat(i) * (s + g), y: y0 + CGFloat(j) * (s + g), width: s, height: s)
                let p = NSBezierPath(roundedRect: r, xRadius: 1.8, yRadius: 1.8)
                if (i, j) == (1, 1) { p.lineWidth = 1.3; p.stroke() } else { p.fill() }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
