import AppKit
import ApplicationServices
import ShelfCore

/// A status item owned by another app, read from the public CGWindowList API.
/// Window bounds and owner names need no Screen Recording permission.
struct MenuBarItem: Identifiable, Equatable {
    let id: CGWindowID
    let pid: pid_t
    let ownerName: String
    /// Core Graphics coordinates (top-left origin), as AX also uses.
    let cgFrame: CGRect
    /// Cocoa coordinates (bottom-left origin).
    let frame: CGRect
    /// kCGWindowName. macOS returns it only when Shelf has Screen Recording,
    /// which Shelf does not request, so this is normally nil.
    let windowName: String?
}

enum MenuBarItems {
    /// kCGStatusWindowLevel
    private static let statusLayer = 25
    /// kCGPopUpMenuWindowLevel
    private static let popUpMenuLayer = 101

    /// All other apps' status items, sorted left to right. Includes items pushed offscreen.
    static func all() -> [MenuBarItem] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let screenTopsCG = NSScreen.screens.map { primaryHeight - $0.frame.maxY }
        let maxHeight = max(NSStatusBar.system.thickness, NSScreen.screens.map(\.safeAreaInsets.top).max() ?? 0) + 2
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info -> MenuBarItem? in
            guard (info[kCGWindowLayer as String] as? Int) == statusLayer,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let cgFrame = CGRect(dictionaryRepresentation: boundsDict),
                  cgFrame.width < 1000,
                  MenuBarGeometry.isMenuBarItemWindow(cgFrame: cgFrame, screenTopsCG: screenTopsCG, maxHeight: maxHeight)
            else { return nil }
            let owner = info[kCGWindowOwnerName as String] as? String ?? "Unknown"
            return MenuBarItem(
                id: id, pid: pid, ownerName: owner, cgFrame: cgFrame,
                frame: MenuBarGeometry.cocoaRect(fromCG: cgFrame, primaryScreenHeight: primaryHeight),
                windowName: (info[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 }
            )
        }
        .sorted { $0.frame.minX < $1.frame.minX }
    }

    /// True while any pop-up menu (e.g. one opened from a revealed item) is on screen.
    static func isMenuOpen() -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        return list.contains { ($0[kCGWindowLayer as String] as? Int) == popUpMenuLayer }
    }

    // MARK: Identity (v2 keys, uses Accessibility when trusted)

    /// An item plus its saved-choice key and display details.
    struct Described {
        let item: MenuBarItem
        let key: String
        let owner: String // bundle ID, or owner name when there is none
        let appName: String
        /// Row name from ItemNaming (window name, known identifier, AX title,
        /// description, or "<App> (item N)"). Display only, never part of the key.
        let name: String
        let icon: NSImage?
        let element: AXUIElement?
    }

    private struct AXInfo {
        let element: AXUIElement
        let x: CGFloat
        let identifier: String?
        let title: String?
        let detail: String?
    }

    /// Items with v2 keys. With Accessibility, windows that match no AX
    /// element (such as Control Center's hidden extra window) are dropped.
    /// Without it, keys fall back to owner + position.
    static func describe() -> [Described] {
        let items = all()
        let trusted = AXIsProcessTrusted()
        var axByPID: [pid_t: [AXInfo]] = [:]
        var used = Set<String>()
        var kept: [(MenuBarItem, AXInfo?)] = []
        for item in items {
            var info: AXInfo?
            if trusted {
                let children = axByPID[item.pid] ?? extras(of: item.pid)
                axByPID[item.pid] = children
                if !children.isEmpty {
                    guard let index = ItemIdentity.axMatch(windowMinX: item.cgFrame.minX, windowMaxX: item.cgFrame.maxX,
                                                           axXs: children.map(\.x)),
                          used.insert("\(item.pid):\(index)").inserted else { continue }
                    info = children[index]
                }
            }
            kept.append((item, info))
        }
        let apps = kept.map { NSRunningApplication(processIdentifier: $0.0.pid) }
        let probes = kept.indices.map { i -> ItemProbe in
            let (item, info) = kept[i]
            return ItemProbe(owner: apps[i]?.bundleIdentifier ?? item.ownerName,
                             appName: apps[i]?.localizedName ?? item.ownerName, minX: item.frame.minX,
                             windowName: item.windowName, title: info?.title, detail: info?.detail,
                             identifier: info?.identifier)
        }
        let keys = ItemIdentity.keys(probes.map(\.identityInput))
        let names = ItemNaming.names(probes)
        return kept.indices.map { i in
            Described(item: kept[i].0, key: keys[i], owner: probes[i].owner, appName: probes[i].appName,
                      name: names[i], icon: apps[i]?.icon, element: kept[i].1?.element)
        }
    }

    /// Version-1 keys (owner + index) for the same items, used only for migration.
    static func legacyKeys(_ described: [Described]) -> [String] {
        ItemKey.keys(owners: described.map(\.owner), minXs: described.map(\.item.frame.minX))
    }

    private static func extras(of pid: pid_t) -> [AXInfo] {
        let app = AXUIElementCreateApplication(pid)
        guard let bar = element(app, kAXExtrasMenuBarAttribute),
              let children = copy(bar, kAXChildrenAttribute) as? [AXUIElement] else { return [] }
        return children.map { child in
            AXInfo(element: child, x: positionX(child),
                   identifier: string(child, "AXIdentifier"),
                   title: string(child, kAXTitleAttribute),
                   detail: string(child, kAXDescriptionAttribute))
        }
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(parent, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement) // checked by CFGetTypeID above
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let s = copy(element, attribute) as? String, !s.isEmpty else { return nil }
        return s
    }

    // MARK: Clicking items (requires Accessibility)

    static var canPress: Bool { AXIsProcessTrusted() }

    /// Presses an item's AX element (from `describe()`).
    @discardableResult
    static func press(element: AXUIElement) -> Bool {
        guard canPress else { return false }
        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    /// Presses another app's status item through its AX "extras menu bar".
    /// Returns false when Accessibility is not granted or no element matches.
    @discardableResult
    static func press(_ item: MenuBarItem) -> Bool {
        guard canPress else { return false }
        let app = AXUIElementCreateApplication(item.pid)
        var barValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXExtrasMenuBarAttribute as CFString, &barValue) == .success,
              let barValue, CFGetTypeID(barValue) == AXUIElementGetTypeID() else { return false }
        let bar = barValue as! AXUIElement // checked by CFGetTypeID above
        var childrenValue: CFTypeRef?
        AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &childrenValue)
        guard let children = childrenValue as? [AXUIElement], !children.isEmpty else { return false }
        let target = children.min { abs(positionX($0) - item.cgFrame.minX) < abs(positionX($1) - item.cgFrame.minX) }
        guard let target else { return false }
        return AXUIElementPerformAction(target, kAXPressAction as CFString) == .success
    }

    private static func positionX(_ element: AXUIElement) -> CGFloat {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return .greatestFiniteMagnitude }
        var point = CGPoint.zero
        AXValueGetValue(value as! AXValue, .cgPoint, &point) // checked by CFGetTypeID above
        return point.x
    }

    /// Explains why Accessibility is needed. Opens System Settings only if the user asks;
    /// never changes any setting.
    static func explainAccessibility(feature: String) {
        let alert = NSAlert()
        alert.messageText = "Shelf needs Accessibility to \(feature)"
        alert.informativeText = """
        Shelf clicks other apps' menu bar items through the Accessibility API. \
        It does not read your typing or screen. Turn on Shelf in \
        System Settings › Privacy & Security › Accessibility, then try again.
        """
        alert.addButton(withTitle: "Open Privacy Settings")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
