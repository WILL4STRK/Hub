import CoreGraphics
import Foundation
import ShelfCore

// Minimal assertion harness (XCTest is not available with Command Line Tools).
var total = 0
var failed = 0

func check(_ condition: Bool, _ name: String, line: Int = #line) {
    total += 1
    if !condition {
        failed += 1
        print("FAIL [line \(line)] \(name)")
    }
}

// MARK: Sections

do {
    let collapsed = SectionLayout.lengths(for: .collapsed)
    check(collapsed.hidden == SectionLayout.expandedLength, "collapsed pushes hidden section offscreen")
    check(collapsed.alwaysHidden == SectionLayout.expandedLength, "collapsed pushes always-hidden offscreen")

    let shown = SectionLayout.lengths(for: .showHidden)
    check(shown.hidden == SectionLayout.dividerLength, "showHidden shrinks hidden divider")
    check(shown.alwaysHidden == SectionLayout.expandedLength, "showHidden keeps always-hidden offscreen")

    let all = SectionLayout.lengths(for: .showAll)
    check(all.hidden == SectionLayout.dividerLength && all.alwaysHidden == SectionLayout.dividerLength,
          "showAll shrinks both dividers")

    check(SectionLayout.toggled(.collapsed) == .showHidden, "toggle from collapsed reveals hidden")
    check(SectionLayout.toggled(.showHidden) == .collapsed, "toggle from showHidden collapses")
    check(SectionLayout.toggled(.showAll) == .collapsed, "toggle from showAll collapses")

    let hiddenDivider = CGRect(x: 1000, y: 0, width: 14, height: 24)
    let alwaysDivider = CGRect(x: 800, y: 0, width: 14, height: 24)
    func section(_ x: CGFloat) -> MenuSection {
        SectionLayout.section(itemFrame: CGRect(x: x, y: 0, width: 30, height: 24),
                              hiddenDivider: hiddenDivider, alwaysHiddenDivider: alwaysDivider)
    }
    check(section(1100) == .visible, "item right of hidden divider is visible")
    check(section(900) == .hidden, "item between dividers is hidden")
    check(section(700) == .alwaysHidden, "item left of always-hidden divider is always-hidden")
    check(SectionLayout.section(itemFrame: CGRect(x: 700, y: 0, width: 30, height: 24),
                                hiddenDivider: hiddenDivider, alwaysHiddenDivider: nil) == .hidden,
          "without always-hidden divider, left items are hidden")
}

// MARK: Geometry

do {
    let cocoa = MenuBarGeometry.cocoaRect(fromCG: CGRect(x: 10, y: 0, width: 30, height: 24), primaryScreenHeight: 900)
    check(cocoa == CGRect(x: 10, y: 876, width: 30, height: 24), "CG to Cocoa flips y")

    let strip = MenuBarGeometry.menuBarStrip(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), thickness: 24)
    check(strip == CGRect(x: 0, y: 876, width: 1440, height: 24), "menu bar strip at top of screen")

    let items = [CGRect(x: 1300, y: 876, width: 40, height: 24)]
    func empty(_ x: CGFloat, _ y: CGFloat) -> Bool {
        MenuBarGeometry.isEmptyMenuBarPoint(CGPoint(x: x, y: y), strip: strip, statusItemFrames: items, appMenuMaxX: 720)
    }
    check(empty(1000, 890), "gap between app menus and items is empty")
    check(empty(1000, 900), "top edge of menu bar counts")
    check(!empty(1310, 890), "point on a status item is not empty")
    check(!empty(300, 890), "point over app menus is not empty")
    check(!empty(1000, 500), "point below menu bar is not empty")
}

// MARK: Notch (fake screens: this Mac has no notch)

do {
    let plain = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), safeAreaTop: 0,
                           auxiliaryTopLeft: nil, auxiliaryTopRight: nil)
    check(NotchLayout.notchRect(plain) == nil, "no notch without safe area")
    check(!NotchLayout.shouldUseBar(screen: plain, visibleSectionMinX: 1200, hiddenItemsWidth: 2000),
          "never use bar without notch")

    // 14" MacBook Pro style: notch between x=661 and x=851.
    let notched = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
                             auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 661, height: 32),
                             auxiliaryTopRight: CGRect(x: 851, y: 950, width: 661, height: 32))
    check(NotchLayout.notchRect(notched) == CGRect(x: 661, y: 950, width: 190, height: 32), "notch rect between aux areas")
    check(!NotchLayout.shouldUseBar(screen: notched, visibleSectionMinX: 1200, hiddenItemsWidth: 200),
          "few hidden items fit right of notch")
    check(NotchLayout.shouldUseBar(screen: notched, visibleSectionMinX: 1200, hiddenItemsWidth: 400),
          "many hidden items would overflow behind notch")
    check(!NotchLayout.shouldUseBar(screen: notched, visibleSectionMinX: 1200, hiddenItemsWidth: 0),
          "nothing hidden means no bar")
}

// MARK: Hotkeys and rehide

do {
    let mods = HotKeySpec.modifiers(command: true, option: true, control: false, shift: false)
    let spec = HotKeySpec(keyCode: 11, modifiers: mods, key: "B")
    check(spec.display == "⌥⌘B", "hotkey display order")
    check(spec.isValid, "⌥⌘ shortcut is valid")
    check(!HotKeySpec(keyCode: 11, modifiers: HotKeySpec.shift, key: "B").isValid, "shift-only shortcut is invalid")
    let decoded = try? JSONDecoder().decode(HotKeySpec.self, from: JSONEncoder().encode(spec))
    check(decoded == spec, "hotkey round-trips through JSON")

    check(RehidePolicy.clamp(0) == 1 && RehidePolicy.clamp(500) == 60, "rehide seconds clamped to 1...60")
    check(RehidePolicy.decide(pointerInMenuBar: false, menuOpen: false) == .rehide, "rehide when idle")
    check(RehidePolicy.decide(pointerInMenuBar: true, menuOpen: false) == .wait(2), "wait while pointer in menu bar")
    check(RehidePolicy.decide(pointerInMenuBar: false, menuOpen: true) == .wait(2), "wait while a menu is open")
}

// MARK: Arrangement

do {
    // Right to left: [always 986..1000][hidden 1000..1014][chevron 1014..1052][visible items...]
    let toggle = CGRect(x: 1014, y: 0, width: 38, height: 24)
    let hidden = CGRect(x: 1000, y: 0, width: 14, height: 24)
    let always = CGRect(x: 986, y: 0, width: 14, height: 24)
    func drop(_ s: MenuSection, always a: CGRect? = always) -> CGPoint? {
        DropPlan.dropPoint(for: s, toggle: toggle, hiddenDivider: hidden, alwaysHiddenDivider: a)
    }
    if let visible = drop(.visible) {
        check(visible.x > toggle.maxX, "visible drop is right of the chevron's maxX")
    } else { check(false, "visible drop exists") }
    check(drop(.hidden) == CGPoint(x: 1002, y: 12), "hidden drop lands on left part of hidden divider")
    check(drop(.alwaysHidden) == CGPoint(x: 988, y: 12), "always-hidden drop lands on left part of always divider")
    check(drop(.alwaysHidden, always: nil) == nil, "no always-hidden drop when that section is off")
    let between = CGRect(x: 1005, y: 0, width: 8, height: 24) // between hidden divider and chevron
    check(SectionLayout.section(itemFrame: between, hiddenDivider: CGRect(x: 990, y: 0, width: 14, height: 24),
                                alwaysHiddenDivider: always, toggle: toggle) == .hidden,
          "item left of the chevron is not visible")
    check(SectionLayout.section(itemFrame: CGRect(x: 1060, y: 0, width: 30, height: 24), hiddenDivider: hidden,
                                alwaysHiddenDivider: always, toggle: toggle) == .visible,
          "item right of the chevron is visible")
    check(drop(.alwaysHidden)!.x < drop(.hidden)!.x && drop(.hidden)!.x < drop(.visible)!.x,
          "drop points ordered always-hidden < hidden < visible")

    let keys = ItemKey.keys(owners: ["com.apple.controlcenter", "com.a", "com.apple.controlcenter"], minXs: [500, 100, 300])
    check(keys == ["com.apple.controlcenter#1", "com.a#0", "com.apple.controlcenter#0"],
          "item keys index each owner's items left to right")
    let sections: [String: MenuSection] = ["com.a#0": .alwaysHidden]
    let decodedSections = try? JSONDecoder().decode([String: MenuSection].self, from: JSONEncoder().encode(sections))
    check(decodedSections == sections, "item sections round-trip through JSON")
}

// MARK: Item identity (v2 keys)

do {
    let cc = "com.apple.controlcenter"
    let items = [
        ItemIdentityInput(owner: cc, minX: 1400, identifier: "com.apple.menuextra.wifi"),
        ItemIdentityInput(owner: cc, minX: 1300, identifier: "com.apple.menuextra.sound"),
        ItemIdentityInput(owner: "com.apple.Spotlight", minX: 1450, title: "Spotlight"),
        ItemIdentityInput(owner: "com.1password.1password", minX: 1100),
    ]
    let keys = ItemIdentity.keys(items)
    check(keys == ["\(cc)|id:com.apple.menuextra.wifi", "\(cc)|id:com.apple.menuextra.sound",
                   "com.apple.Spotlight|title:Spotlight", "com.1password.1password#0"],
          "keys prefer AX identifier, then title, then position")

    // Reorder Control Center items: keys must follow the items, not positions.
    var swapped = items
    swapped[0].minX = 1300
    swapped[1].minX = 1400
    check(ItemIdentity.keys(swapped) == keys, "reordering Control Center items keeps each item's key")

    let twins = [ItemIdentityInput(owner: "x", minX: 20, identifier: "same"), ItemIdentityInput(owner: "x", minX: 10, identifier: "same")]
    check(ItemIdentity.keys(twins) == ["x|id:same#1", "x|id:same"], "duplicate identifiers get #k suffix left to right")
    let blanks = [ItemIdentityInput(owner: "y", minX: 50, identifier: "", title: ""), ItemIdentityInput(owner: "y", minX: 5)]
    check(ItemIdentity.keys(blanks) == ["y#1", "y#0"], "empty identifier/title fall back to position")

    check(ItemIdentity.axMatch(windowMinX: -3932, windowMaxX: -3894, axXs: [-3924, 1352, 1385]) == 0,
          "AX element inside window span matches")
    check(ItemIdentity.axMatch(windowMinX: 1306, windowMaxX: 1344, axXs: [-3924, 1352, 1385]) == nil,
          "hidden extra window with no AX element has no match")

    let migration = ItemIdentity.migrate(
        saved: ["\(cc)#0": .hidden, "com.1password.1password#0": .visible, "gone#0": .hidden],
        legacyKeys: ["\(cc)#0", "\(cc)#1", "com.1password.1password#0"],
        newKeys: ["\(cc)|id:com.apple.menuextra.sound", "\(cc)|id:com.apple.menuextra.wifi", "com.1password.1password#0"])
    check(migration.saved == ["\(cc)|id:com.apple.menuextra.sound": .hidden, "com.1password.1password#0": .visible],
          "migration maps legacy keys to v2 keys")
    check(migration.mapping.contains(ItemIdentity.Mapping(old: "gone#0", new: nil, section: .hidden)),
          "migration reports keys with no current item as dropped")
}

// MARK: Search ranking

do {
    check(SearchRank.score(query: "", fields: ["Anything"]) == 0, "empty query matches everything")
    check(SearchRank.score(query: "zzz", fields: ["Control Center", "Battery"]) == nil, "no match returns nil")
    let exact = SearchRank.score(query: "battery", fields: ["Control Center", "Battery"]) ?? -1
    let prefix = SearchRank.score(query: "bat", fields: ["Control Center", "Battery"]) ?? -1
    let inner = SearchRank.score(query: "tter", fields: ["Control Center", "Battery"]) ?? -1
    check(exact > prefix && prefix > inner && inner > 0, "exact > prefix > substring")
    check(SearchRank.score(query: "wi", fields: ["Control Center", "Wi‑Fi"]) != nil, "prefix of a label matches")
    check((SearchRank.score(query: "center", fields: ["Control Center"]) ?? 0) >= 150, "word prefix inside a name ranks above substring")
    check(SearchRank.score(query: "SPOT", fields: ["Spotlight"]) != nil, "case-insensitive")
}

// MARK: Item naming and key stability

do {
    let cc = "com.apple.controlcenter"
    func probe(_ x: CGFloat, id: String? = nil, title: String? = nil, detail: String? = nil, window: String? = nil,
               owner: String = cc, app: String = "Control Center") -> ItemProbe {
        ItemProbe(owner: owner, appName: app, minX: x, windowName: window, title: title, detail: detail, identifier: id)
    }
    check(ItemNaming.friendlyName(identifier: "com.apple.menuextra.wifi") == "Wi‑Fi", "wifi identifier maps to Wi‑Fi")
    check(ItemNaming.friendlyName(identifier: "com.apple.menuextra.now-playing") == "Now Playing", "now-playing maps")
    check(ItemNaming.friendlyName(identifier: "com.apple.menuextra.screenmirroring") == "Screen Mirroring", "screen mirroring maps")
    check(ItemNaming.friendlyName(identifier: "com.apple.menuextra.focusmode") == "Focus", "focusmode maps to Focus")
    check(ItemNaming.friendlyName(identifier: "com.apple.menuextra.new-thing") == "New Thing", "unknown Apple extra is prettified")
    check(ItemNaming.friendlyName(identifier: "com.example.widget") == nil, "non-Apple identifier has no friendly name")

    // Real window names on this Mac: "Item-0", UUIDs, "BentoBox", "NowPlaying".
    check(ItemNaming.label(probe(0, id: "com.apple.menuextra.controlcenter", window: "BentoBox")) == "Control Center",
          "known identifier beats internal window name")
    check(ItemNaming.label(probe(0, window: "Item-0")) == nil, "Item-N window name is ignored")
    check(ItemNaming.label(probe(0, window: "bb3cc23c-6950-4e96-8b40-850e09f46934")) == nil, "UUID window name is ignored")
    check(ItemNaming.label(probe(0, window: "Dropbox Status")) == "Dropbox Status", "meaningful window name used as last resort")
    check(ItemNaming.label(probe(0, id: "com.apple.menuextra.wifi", detail: "Wi‑Fi, connected, 3 bars")) == "Wi‑Fi",
          "known identifier beats changing description")
    check(ItemNaming.label(probe(0, title: "Spotlight", owner: "com.apple.Spotlight", app: "Spotlight")) == "Spotlight",
          "AX title used without identifier")
    check(ItemNaming.label(probe(0, detail: "Bluetooth, 2 devices")) == "Bluetooth", "first clause of description")
    check(ItemNaming.label(probe(0)) == nil, "no data gives no label")

    let rows = [probe(300, id: "com.apple.menuextra.sound"), probe(100), probe(200),
                probe(50, owner: "com.1password.1password", app: "1Password")]
    check(ItemNaming.names(rows) == ["Sound", "Control Center (item 1)", "Control Center (item 2)", "1Password"],
          "unlabeled items numbered per owner; single-item owner shows app name")
    let ccNames = ItemNaming.names([probe(10, id: "com.apple.menuextra.wifi"), probe(20, id: "com.apple.menuextra.battery"),
                                    probe(30, id: "com.apple.menuextra.sound"), probe(40, id: "com.apple.menuextra.clock")])
    check(Set(ccNames).count == ccNames.count, "Control Center rows have distinct names")

    // Key stability: display-only fields never change the saved-choice key.
    let before = probe(10, id: "com.apple.menuextra.wifi", detail: "Wi‑Fi, connected, 3 bars")
    var after = before
    after.detail = "Wi‑Fi, not connected"
    after.windowName = "WiFi"
    check(ItemIdentity.keys([before.identityInput]) == ItemIdentity.keys([after.identityInput]),
          "description or window name change keeps the key")
    check(ItemIdentity.keys([before.identityInput]) == ["\(cc)|id:com.apple.menuextra.wifi"], "key is still v2 identifier key")
}

// MARK: Click routing (only the chevron toggles)

do {
    let strip = CGRect(x: 0, y: 876, width: 1680, height: 24)
    let chevron = CGRect(x: 1084, y: 876, width: 38, height: 24)
    let items = [CGRect(x: 1122, y: 876, width: 38, height: 24)]
    func action(_ x: CGFloat, emptyArea: Bool) -> MenuBarGeometry.ClickAction {
        MenuBarGeometry.clickAction(at: CGPoint(x: x, y: 888), chevron: chevron, strip: strip,
                                    statusItemFrames: items, appMenuMaxX: 840, emptyAreaEnabled: emptyArea)
    }
    for emptyArea in [false, true] {
        let mode = emptyArea ? "empty-area option on" : "default"
        check(action(chevron.minX - 1, emptyArea: emptyArea) == .none, "\(mode): click 1pt left of chevron does not toggle")
        check(action(chevron.minX - 10, emptyArea: emptyArea) == .none, "\(mode): click 10pt left of chevron does not toggle")
        check(action(chevron.minX - 30, emptyArea: emptyArea) == .none, "\(mode): click 30pt left of chevron does not toggle")
        check(action(chevron.midX, emptyArea: emptyArea) == .chevron, "\(mode): click inside chevron toggles")
    }
    check(action(1000, emptyArea: false) == .none, "default: empty-area click is off")
    check(action(1000, emptyArea: true) == .emptyArea, "option on: empty area far from chevron toggles")
    check(action(1130, emptyArea: true) == .none, "click on another item never toggles")
}

// MARK: Item window filter

do {
    let tops: [CGFloat] = [0]
    check(MenuBarGeometry.isMenuBarItemWindow(cgFrame: CGRect(x: 1200, y: 0, width: 40, height: 24), screenTopsCG: tops, maxHeight: 26),
          "real menu bar item passes filter")
    check(!MenuBarGeometry.isMenuBarItemWindow(cgFrame: CGRect(x: 1014, y: 24, width: 358, height: 453), screenTopsCG: tops, maxHeight: 26),
          "Cloudflare WARP dropdown panel is filtered out")
    check(!MenuBarGeometry.isMenuBarItemWindow(cgFrame: CGRect(x: 0, y: 0, width: 300, height: 400), screenTopsCG: tops, maxHeight: 26),
          "tall window at the top edge is filtered out")
}

// MARK: HoverGate (Hub: chevron reopened right after a click while the pointer sat in the hover zone)
do {
    var g = HoverGate()
    check(g.pointerMoved(inZone: true, isShowing: false), "hover in zone reveals when collapsed")
    check(!g.pointerMoved(inZone: true, isShowing: true), "hover does nothing while already showing")
    g.manualClick()  // user clicks the chevron to close; pointer still on it
    check(!g.pointerMoved(inZone: true, isShowing: false), "after a click: no reveal while pointer stays in zone")
    check(!g.pointerMoved(inZone: true, isShowing: false), "after a click: still no reveal on further moves in zone")
    check(!g.pointerMoved(inZone: false, isShowing: false), "leaving the zone never reveals")
    check(!g.suppressed, "leaving the zone clears the lockout")
    check(g.pointerMoved(inZone: true, isShowing: false), "re-entering the zone reveals again")
    var h = HoverGate()
    h.manualClick()  // click to open, then close, pointer never leaves
    _ = h.pointerMoved(inZone: true, isShowing: true)
    h.manualClick()
    check(!h.pointerMoved(inZone: true, isShowing: false), "open-then-close by clicks: no reopen in zone")
}

// MARK: ArrangeLock and MoveCheck (Hub: moves failed about half the time)
do {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    var l = ArrangeLock()
    check(!l.blocks(at: t0), "lock: idle does not block")
    l.beginSession()
    check(l.blocks(at: t0), "lock: session blocks collapse")
    l.beginDrag()
    check(l.blocks(at: t0), "lock: mouse-down to mouse-up blocks")
    l.endSession()
    check(l.blocks(at: t0), "lock: drag still blocks after session ends")
    l.endDrag(at: t0)
    check(l.blocks(at: t0.addingTimeInterval(0.2)), "lock: blocks during settle (collapse 0.2 s after mouse-up)")
    check(l.blocks(at: t0.addingTimeInterval(ArrangeLock.settle - 0.01)), "lock: blocks until the settle delay ends")
    check(!l.blocks(at: t0.addingTimeInterval(ArrangeLock.settle + 0.01)), "lock: releases after the settle delay")

    let screen = CGRect(x: 0, y: 0, width: 1680, height: 1050)
    check(!MoveCheck.isOnScreen(CGRect(x: -3804, y: 0, width: 24, height: 24), screens: [screen]), "start: collapsed item (x=-3804) is off screen")
    check(MoveCheck.isOnScreen(CGRect(x: 1000, y: 0, width: 24, height: 24), screens: [screen]), "start: item at x=1000 is on screen")
    check(!MoveCheck.isOnScreen(CGRect(x: 1670, y: 0, width: 24, height: 24), screens: [screen]), "start: item past the right edge is off screen")
    check(!MoveCheck.isOnScreen(CGRect(x: -10, y: 0, width: 24, height: 24), screens: [screen]), "start: item past the left edge is off screen")
    check(MoveCheck.isOnScreen(CGRect(x: -900, y: 0, width: 24, height: 24),
                               screens: [screen, CGRect(x: -1440, y: 0, width: 1440, height: 900)]), "start: item on a second screen counts")

    check(MoveCheck.outcome(landed: true, attempt: 1) == .done, "verify: landed -> done")
    check(MoveCheck.outcome(landed: false, attempt: 1) == .retry, "verify: missed once -> retry")
    check(MoveCheck.outcome(landed: false, attempt: 2) == .failed, "verify: missed twice -> error")
    check(MoveCheck.outcome(landed: true, attempt: 2) == .done, "verify: landed on retry -> done")
}

print("\(total - failed)/\(total) checks passed")
exit(failed == 0 ? 0 : 1)
