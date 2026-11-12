import Foundation
import HubCore

/// Runs Migration once, on Hub's first launch, before any module reads its settings.
/// Reads the old apps' domains; never writes to or deletes them.
enum SettingsMigration {
    static func runIfNeeded(_ defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: Migration.flagKey) else { return }
        let plan = Migration.plan(
            awning: defaults.persistentDomain(forName: Migration.awningDomain),
            shelf: defaults.persistentDomain(forName: Migration.shelfDomain),
            widgets: defaults.persistentDomain(forName: Migration.widgetsDomain),
            existing: defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "local.hub.Hub") ?? [:])
        for (key, value) in plan.values { defaults.set(value, forKey: key) }
        let stamp = ISO8601DateFormatter().string(from: Date())
        defaults.set(["\(stamp): \(plan.values.count) settings copied"] + plan.lines, forKey: Migration.reportKey)
        defaults.set(true, forKey: Migration.flagKey)
        NSLog("Hub: settings migration copied %d values", plan.values.count)
    }

    /// The first migration copied Awning's hover onto showOnHoverNearChevron, which made the chevron reopen
    /// right after a click. Turn it off once, only if that copy is where the value came from.
    static func repairHoverIfNeeded(_ defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: Migration.hoverFixKey) else { return }
        defaults.set(true, forKey: Migration.hoverFixKey)
        guard report.contains(Migration.hoverFixReportLine) else { return }
        defaults.set(false, forKey: "showOnHoverNearChevron")
        defaults.set(report + ["repair: showOnHoverNearChevron set off (Awning's hover is no longer copied)"], forKey: Migration.reportKey)
        NSLog("Hub: turned showOnHoverNearChevron off (repair of the first migration)")
    }

    static var report: [String] { UserDefaults.standard.stringArray(forKey: Migration.reportKey) ?? [] }
}
