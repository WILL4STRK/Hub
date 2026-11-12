import AppKit

struct ScreenChoice: Identifiable, Hashable {
    let id: String
    let name: String
}

/// Finds the screen to host the island and the notch geometry on it.
enum ScreenLocator {
    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }

    /// The chosen screen, falling back to: a screen with a notch, the built-in screen, the main screen.
    static func target(id: String) -> NSScreen? {
        let screens = NSScreen.screens
        if id != "auto", let wanted = UInt32(id),
           let match = screens.first(where: { displayID($0) == wanted }) {
            return match
        }
        return screens.first(where: { notchSize(of: $0) != nil })
            ?? screens.first(where: { CGDisplayIsBuiltin(displayID($0)) != 0 })
            ?? NSScreen.main
    }

    /// Size of the real camera housing, or nil when the screen has none.
    static func notchSize(of screen: NSScreen) -> CGSize? {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return nil }
        return CGSize(width: screen.frame.width - left.width - right.width,
                      height: screen.safeAreaInsets.top)
    }

    /// Size used when simulating a notch. Height 0 means "match the menu bar".
    static func simulatedSize(of screen: NSScreen, width: Double, height: Double) -> CGSize {
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        let h = height > 0 ? height : Double(max(24, min(menuBar, 38)))
        return CGSize(width: min(max(width, 120), 360), height: min(max(h, 20), 44))
    }

    static func choices() -> [ScreenChoice] {
        NSScreen.screens.map { screen in
            let suffix = notchSize(of: screen) != nil ? " (notch)" : ""
            return ScreenChoice(id: String(displayID(screen)), name: screen.localizedName + suffix)
        }
    }
}
