import Foundation

/// One-time copy of the three old apps' settings into Hub's own domain (local.hub.Hub).
/// Pure: takes the old domains as dictionaries and returns what to write. It never writes or
/// deletes anything in the old domains.
public enum Migration {
    public static let flagKey = "hub.migrated.v1"
    public static let reportKey = "hub.migrationReport"
    /// One-time repair for Hubs that already ran the first version of the migration.
    public static let hoverFixKey = "hub.fix.hoverNearChevronOff.v1"
    public static let hoverFixReportLine = "copied app.awning.Awning menuBarShowOnHover -> showOnHoverNearChevron"
    public static let awningDomain = "app.awning.Awning"
    public static let shelfDomain = "local.shelf.Shelf"
    public static let widgetsDomain = "com.claude-widgets"

    /// Awning keys Hub does not take: its own status-item positions, its launch-at-login flag,
    /// and its menu-bar hider (Shelf's hider is kept; only hover and tint come across).
    static func awningKeyIsSkipped(_ key: String) -> Bool {
        if key.hasPrefix("NSStatusItem") { return true }
        if key == "launchAtLoginAutoApplied" { return true }
        if key.hasPrefix("menuBar"), !awningMenuBarKeysKept.keys.contains(key) { return true }
        return false
    }

    /// Awning menu-bar keys that come across, with their name in Hub. menuBarShowOnHover is NOT mapped onto
    /// showOnHoverNearChevron: that hover reopened the sections right after a chevron click (owner, 2026-11-12).
    static let awningMenuBarKeysKept: [String: String] = [
        "menuBarTint": "menuBarTint",
        "menuBarTintColor": "menuBarTintColor",
    ]

    public struct Plan {
        /// Key/value pairs to write into Hub's domain.
        public var values: [String: Any] = [:]
        /// Human-readable lines: "copied", "skipped", "kept" (already set in Hub), "conflict".
        public var lines: [String] = []
    }

    /// Order: Awning, then Claude Widgets, then Shelf, so Shelf's value wins any clash.
    /// A key that Hub already has is never overwritten.
    public static func plan(awning: [String: Any]?, shelf: [String: Any]?, widgets: [String: Any]?,
                            existing: [String: Any]) -> Plan {
        var plan = Plan()
        var source: [String: String] = [:]

        func take(_ domain: String, _ key: String, as target: String, _ value: Any) {
            if existing[target] != nil {
                plan.lines.append("kept \(target) (already set in Hub)")
                return
            }
            if let previous = source[target] {
                plan.lines.append("conflict \(target): \(domain) wins over \(previous)")
            }
            plan.values[target] = value
            source[target] = domain
            plan.lines.append("copied \(domain) \(key)" + (key == target ? "" : " -> \(target)"))
        }

        for (key, value) in (awning ?? [:]).sorted(by: { $0.key < $1.key }) {
            if awningKeyIsSkipped(key) {
                plan.lines.append("skipped \(awningDomain) \(key)")
                continue
            }
            take(awningDomain, key, as: awningMenuBarKeysKept[key] ?? key, value)
        }
        for (key, value) in (widgets ?? [:]).sorted(by: { $0.key < $1.key }) {
            take(widgetsDomain, key, as: key, value)
        }
        for (key, value) in (shelf ?? [:]).sorted(by: { $0.key < $1.key }) {
            take(shelfDomain, key, as: key, value)
        }
        if awning == nil { plan.lines.append("missing \(awningDomain)") }
        if shelf == nil { plan.lines.append("missing \(shelfDomain)") }
        if widgets == nil { plan.lines.append("missing \(widgetsDomain)") }
        return plan
    }
}

/// Which module each old app clashes with. While a listed app runs, Hub keeps that module paused,
/// so the old and new copies never fight over the notch, the menu bar or the desktop.
public enum HubModuleID: String, CaseIterable {
    case widgets, island, menuBar

    public var title: String {
        switch self {
        case .widgets: return "Widgets"
        case .island: return "Island"
        case .menuBar: return "Menu Bar"
        }
    }

    /// Bundle ids of old apps that clash. Awning also clashes with the Menu Bar module (its own hider).
    public var blockingBundleIDs: [String] {
        switch self {
        case .widgets: return [Migration.widgetsDomain]
        case .island: return [Migration.awningDomain]
        case .menuBar: return [Migration.shelfDomain, Migration.awningDomain]
        }
    }

    public var enabledKey: String { "hub.module.\(rawValue).enabled" }

    /// Names of running old apps that keep this module paused.
    public func blockers(running: Set<String>) -> [String] {
        blockingBundleIDs.filter(running.contains).map(HubModuleID.appName)
    }

    public static func appName(_ bundleID: String) -> String {
        switch bundleID {
        case Migration.awningDomain: return "Awning"
        case Migration.shelfDomain: return "Shelf"
        case Migration.widgetsDomain: return "Claude Widgets"
        default: return bundleID
        }
    }
}
