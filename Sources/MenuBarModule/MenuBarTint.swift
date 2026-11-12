import AppKit

/// Optional color tint over the menu bar (from Awning). Click-through, all Spaces.
final class MenuBarTint {
    private let settings: AppSettings
    private var screenObserver: Any?
    private var panels: [NSPanel] = []

    init(settings: AppSettings) {
        self.settings = settings
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in self?.apply() }
        apply()
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        panels.forEach { $0.orderOut(nil) }
    }

    private var lastSignature = ""

    /// Rebuilds the panels only when the tint settings changed.
    func applyIfChanged() {
        let sig = "\(settings.menuBarTint)|\(settings.menuBarTintColor)"
        guard sig != lastSignature else { return }
        apply()
    }

    func apply() {
        lastSignature = "\(settings.menuBarTint)|\(settings.menuBarTintColor)"
        panels.forEach { $0.orderOut(nil) }
        panels = []
        guard settings.menuBarTint, let color = NSColor(hex: settings.menuBarTintColor) else { return }
        for screen in NSScreen.screens {
            let bar = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
            let rect = NSRect(x: screen.frame.minX, y: screen.frame.maxY - bar, width: screen.frame.width, height: bar)
            let p = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = color.withAlphaComponent(0.28)
            p.hasShadow = false
            p.ignoresMouseEvents = true
            p.level = .mainMenu
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            p.isReleasedWhenClosed = false
            p.animationBehavior = .none // removed in the same frame, no fade
            p.orderFrontRegardless()
            panels.append(p)
        }
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}
