import CoreGraphics
import Foundation

/// Everything Shelf can read about one item. Only `identifier` and `title`
/// feed the saved-choice key (ItemIdentity). The rest is display only.
public struct ItemProbe: Equatable {
    public var owner: String // bundle ID or owner name
    public var appName: String
    public var minX: CGFloat
    /// kCGWindowName: only present when Shelf has Screen Recording.
    public var windowName: String?
    public var title: String?
    /// AXDescription. Can change with state ("Wi-Fi, connected, 3 bars").
    public var detail: String?
    public var identifier: String?

    public init(owner: String, appName: String, minX: CGFloat, windowName: String? = nil,
                title: String? = nil, detail: String? = nil, identifier: String? = nil) {
        self.owner = owner
        self.appName = appName
        self.minX = minX
        self.windowName = windowName
        self.title = title
        self.detail = detail
        self.identifier = identifier
    }

    public var identityInput: ItemIdentityInput {
        ItemIdentityInput(owner: owner, minX: minX, identifier: identifier, title: title)
    }
}

public enum ItemNaming {
    /// Friendly names for Apple menu extras (identifier suffix after "com.apple.menuextra.").
    public static let menuExtraNames: [String: String] = [
        "wifi": "Wi‑Fi", "bluetooth": "Bluetooth", "sound": "Sound", "volume": "Sound",
        "battery": "Battery", "focusmode": "Focus", "display": "Display", "airdrop": "AirDrop",
        "now-playing": "Now Playing", "screenmirroring": "Screen Mirroring", "airplay": "Screen Mirroring",
        "clock": "Clock", "controlcenter": "Control Center", "keyboardbrightness": "Keyboard Brightness",
        "textinput": "Input Source", "user": "Fast User Switching", "accessibility": "Accessibility Shortcuts",
        "hearing": "Hearing", "siri": "Siri", "spotlight": "Spotlight", "timemachine": "Time Machine",
        "vpn": "VPN", "stagemanager": "Stage Manager", "eject": "Eject", "script": "Script Menu",
    ]

    public static func friendlyName(identifier: String?) -> String? {
        guard let id = identifier?.trimmingCharacters(in: .whitespaces), !id.isEmpty else { return nil }
        let prefix = "com.apple.menuextra."
        let suffix = id.hasPrefix(prefix) ? String(id.dropFirst(prefix.count)) : id
        if let known = menuExtraNames[suffix.lowercased()] { return known }
        guard id.hasPrefix(prefix) else { return nil }
        // Unknown Apple extra: "foo-bar" -> "Foo Bar".
        return suffix.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == "." })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Window names are often internal autosave names ("Item-0", UUIDs,
    /// "BentoBox", "NowPlaying"), so they rank last and these patterns are ignored.
    public static func isMeaningfulWindowName(_ name: String) -> Bool {
        if name.range(of: #"^Item-\d+$"#, options: .regularExpression) != nil { return false }
        if UUID(uuidString: name) != nil { return false }
        return true
    }

    /// Label from one item's own data, or nil when it has none.
    /// Order: known identifier, AXTitle, first clause of AXDescription,
    /// window name (when meaningful), raw identifier.
    public static func label(_ p: ItemProbe) -> String? {
        func clean(_ s: String?) -> String? {
            guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
            return t
        }
        if let friendly = friendlyName(identifier: p.identifier) { return friendly }
        if let title = clean(p.title) { return title }
        if let detail = clean(p.detail) {
            return clean(String(detail.split(separator: ",", maxSplits: 1).first ?? "")) ?? detail
        }
        if let name = clean(p.windowName), isMeaningfulWindowName(name) { return name }
        return clean(p.identifier)
    }

    /// Row names for all items. Owners with one item show the app name.
    /// An item with no label in a multi-item owner gets "<App> (item N)",
    /// numbered left to right among that owner's unlabeled items.
    public static func names(_ probes: [ItemProbe]) -> [String] {
        let counts = Dictionary(probes.map { ($0.owner, 1) }, uniquingKeysWith: +)
        let order = probes.indices.sorted { probes[$0].minX < probes[$1].minX }
        var unlabeled: [String: Int] = [:]
        var result = Array(repeating: "", count: probes.count)
        for i in order {
            let p = probes[i]
            if let label = label(p) {
                result[i] = label
            } else if counts[p.owner, default: 0] > 1 {
                let n = unlabeled[p.owner, default: 0] + 1
                unlabeled[p.owner] = n
                result[i] = "\(p.appName) (item \(n))"
            } else {
                result[i] = p.appName
            }
        }
        return result
    }
}
