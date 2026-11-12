import Foundation
import HubCore

var passed = 0
var failed = 0
func check(_ name: String, _ ok: Bool) {
    if ok { passed += 1; print("PASS \(name)") } else { failed += 1; print("FAIL \(name)") }
}

// Fixtures shaped like the real domains on this Mac (2026-11-12).
let awning: [String: Any] = [
    "NSStatusItem Preferred Position Item-0": 734,
    "NSStatusItem Preferred Position awning.hider.divider": 798,
    "NSStatusItem Preferred Position awning.hider.toggle": 772,
    "defaultPlayer": "spotify", "launchAtLoginAutoApplied": true, "lockCardHeight": 185,
    "menuBarHider": true, "menuBarShowOnHover": true, "menuBarRehide": "leave", "menuBarHotkey": true,
    "menuBarTint": true, "menuBarTintColor": "#FF0000",
    "notchHeight": 0, "notchWidth": 245, "onboarded": true, "screenID": "auto",
    "showAudioBars": true, "showOnLockScreen": true, "weatherCache": Data([1, 2, 3]),
]
let shelf: [String: Any] = [
    "NSStatusItem Preferred Position ShelfAlwaysHiddenDivider": 670,
    "NSStatusItem Preferred Position ShelfHiddenDivider": 499,
    "NSStatusItem Preferred Position ShelfToggle": 461,
    "NSStatusItem Visible ShelfAlwaysHiddenDivider": true,
    "alwaysHiddenEnabled": true, "itemKeysVersion": 2, "itemSections": Data([7, 7]),
]
let widgets: [String: Any] = [
    "ClaudeWidgets.locked": true,
    "NSWindow Frame ClaudeWidgets.home": "0 417 380 608 0 0 1680 1025 ",
]

let p = Migration.plan(awning: awning, shelf: shelf, widgets: widgets, existing: [:])
let v = p.values

// Awning: island settings copied, hider dropped except hover (renamed) and tint.
check("awning notchWidth copied", v["notchWidth"] as? Int == 245)
check("awning onboarded copied", v["onboarded"] as? Bool == true)
check("awning lock card switch copied", v["showOnLockScreen"] as? Bool == true)
check("awning weather cache copied", v["weatherCache"] as? Data == Data([1, 2, 3]))
check("awning hover NOT mapped to showOnHoverNearChevron (stays off)", v["showOnHoverNearChevron"] == nil)
check("awning menuBarShowOnHover not copied", v["menuBarShowOnHover"] == nil)
check("hover not copied even when Awning had it on", awning["menuBarShowOnHover"] as? Bool == true && v["showOnHoverNearChevron"] == nil)
check("awning tint copied", v["menuBarTint"] as? Bool == true)
check("awning tint colour copied", v["menuBarTintColor"] as? String == "#FF0000")
check("awning hider switch skipped", v["menuBarHider"] == nil)
check("awning rehide skipped (Shelf's rehide wins)", v["menuBarRehide"] == nil)
check("awning hotkey skipped (Shelf's shortcut wins)", v["menuBarHotkey"] == nil)
check("awning status item positions skipped", !v.keys.contains { $0.contains("awning.hider") || $0.hasSuffix("Item-0") })
check("awning launch-at-login flag skipped", v["launchAtLoginAutoApplied"] == nil)

// Shelf: everything copied, including status item positions and item choices.
check("shelf toggle position copied", v["NSStatusItem Preferred Position ShelfToggle"] as? Int == 461)
check("shelf divider visibility copied", v["NSStatusItem Visible ShelfAlwaysHiddenDivider"] as? Bool == true)
check("shelf itemSections copied", v["itemSections"] as? Data == Data([7, 7]))
check("shelf itemKeysVersion copied (no re-migration)", v["itemKeysVersion"] as? Int == 2)
check("shelf alwaysHiddenEnabled copied", v["alwaysHiddenEnabled"] as? Bool == true)

// Widgets: lock and window frame.
check("widgets lock copied", v["ClaudeWidgets.locked"] as? Bool == true)
check("widgets frame copied", v["NSWindow Frame ClaudeWidgets.home"] as? String == "0 417 380 608 0 0 1680 1025 ")

// Every key is accounted for: Awning minus the skipped ones, plus all of Shelf and Claude Widgets.
let skippedAwning = awning.keys.filter { $0.hasPrefix("NSStatusItem") || $0 == "launchAtLoginAutoApplied" || ["menuBarHider", "menuBarRehide", "menuBarHotkey", "menuBarShowOnHover"].contains($0) }.count
check("repair line matches the old report text", Migration.hoverFixReportLine == "copied app.awning.Awning menuBarShowOnHover -> showOnHoverNearChevron")
check("value count = awning kept + shelf + widgets", v.count == awning.count - skippedAwning + shelf.count + widgets.count)

// Shelf wins a clash.
let clash = Migration.plan(awning: ["menuBarTint": false], shelf: ["menuBarTint": true], widgets: nil, existing: [:])
check("clash: shelf value wins", clash.values["menuBarTint"] as? Bool == true)
check("clash: reported", clash.lines.contains { $0.hasPrefix("conflict menuBarTint") })

// Hub's own values are never overwritten.
let kept = Migration.plan(awning: ["notchWidth": 300], shelf: nil, widgets: nil, existing: ["notchWidth": 200])
check("existing Hub value kept", kept.values["notchWidth"] == nil)
check("missing domains reported", kept.lines.contains("missing local.shelf.Shelf") && kept.lines.contains("missing com.claude-widgets"))

// No old domain at all: nothing to write.
let none = Migration.plan(awning: nil, shelf: nil, widgets: nil, existing: [:])
check("no old apps: nothing written", none.values.isEmpty)

// Old apps pause the matching module.
check("Awning pauses Island", HubModuleID.island.blockers(running: ["app.awning.Awning"]) == ["Awning"])
check("Awning pauses Menu Bar (its hider)", HubModuleID.menuBar.blockers(running: ["app.awning.Awning"]) == ["Awning"])
check("Shelf pauses Menu Bar", HubModuleID.menuBar.blockers(running: ["local.shelf.Shelf"]) == ["Shelf"])
check("Claude Widgets pauses Widgets", HubModuleID.widgets.blockers(running: ["com.claude-widgets"]) == ["Claude Widgets"])
check("Shelf does not pause Island", HubModuleID.island.blockers(running: ["local.shelf.Shelf"]).isEmpty)
check("nothing running: nothing paused", HubModuleID.allCases.allSatisfy { $0.blockers(running: []).isEmpty })

print("\(passed)/\(passed + failed) Hub checks passed")
exit(failed == 0 ? 0 : 1)
