import AppKit
import Combine
import ShelfCore

/// Coordinates sections, show triggers, auto-rehide and the notch bar.
final class ShelfController: NSObject {
    let settings: AppSettings
    let itemList = ItemListModel()
    private var sections: SectionController!
    private let hotKey = GlobalHotKey(id: 1)
    private let searchHotKey = GlobalHotKey(id: 2)
    private let search = ItemSearchController()
    let locator = ItemLocator()
    var locateWork: DispatchWorkItem?
    var locateRestoreState: ShelfState?
    private var lastSearchHotKey: HotKeySpec?
    private let notchBar = ShelfBarPanel()
    private var monitors: [Any] = []
    private var settingsObserver: AnyCancellable?
    private var lastHotKey: HotKeySpec?
    private var hoverTimer: Timer?
    private var rehideTimer: Timer?
    private var lastScroll = Date.distantPast
    private var leaveWork: DispatchWorkItem?
    private var hoverGate = HoverGate()
    /// Held while arranging items: no collapse or section change from any trigger (see ShelfCore ArrangeLock).
    var arrangeLock = ArrangeLock()
    var stateChangeBlocked: Bool { arrangeLock.blocks(at: Date()) }
    private var tint: MenuBarTint?
    private var sessionObservers: [(NotificationCenter, Any)] = []
    /// Menu Bar module switched off in Hub: no status items, monitors, shortcuts or tint.
    private(set) var parked = false
    var openSettings: (() -> Void)?
    var quitApp: (() -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
        sections = SectionController(target: self, action: #selector(toggleClicked(_:)))
        sections.apply(.collapsed, alwaysHiddenEnabled: settings.alwaysHiddenEnabled)
        hotKey.onPress = { [weak self] in
            Log.state.info("trigger: hotkey")
            self?.toggle()
        }
        searchHotKey.onPress = { [weak self] in
            Log.arrange.info("search: hotkey")
            self?.search.toggle()
        }
        search.onPick = { [weak self] in self?.openItem($0) }
        applySettings()
        installMonitors()
        tint = MenuBarTint(settings: settings)
        installSessionObservers()
        // objectWillChange fires before the new value is stored; apply on the next turn.
        settingsObserver = settings.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.applySettings() }
        }
        // Local commands from shelf-selftest. Delivered immediately: an
        // accessory app is never "active", so suspended delivery would stall.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleCommand(_:)),
            name: .init(ShelfCommand.notificationName), object: nil, suspensionBehavior: .deliverImmediately)
        // Re-apply saved item sections once other apps' items have appeared.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.migrateItemKeysIfNeeded()
            self?.applyAssignments(reason: "launch re-apply")
        }
    }

    // MARK: Hub module on/off

    func park() {
        guard !parked else { return }
        collapse(force: true)
        parked = true
        hoverTimer?.invalidate(); hoverTimer = nil
        leaveWork?.cancel(); leaveWork = nil
        locateWork?.cancel()
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        hotKey.register(nil); lastHotKey = nil
        searchHotKey.register(nil); lastSearchHotKey = nil
        search.close()
        tint = nil
        sections.remove()
    }

    func unpark() {
        guard parked else { return }
        parked = false
        sections = SectionController(target: self, action: #selector(toggleClicked(_:)))
        sections.apply(.collapsed, alwaysHiddenEnabled: settings.alwaysHiddenEnabled)
        applySettings()
        installMonitors()
        tint = MenuBarTint(settings: settings)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, !self.parked else { return }
            self.migrateItemKeysIfNeeded()
            self.applyAssignments(reason: "module on re-apply")
        }
    }

    /// From Awning: collapse right away on screen lock, display sleep or system sleep.
    private func installSessionObservers() {
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            sessionObservers.append((ws, ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.collapseForSuspend()
            }))
        }
        let dnc = DistributedNotificationCenter.default()
        sessionObservers.append((dnc, dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.collapseForSuspend()
        }))
    }

    private func collapseForSuspend() {
        guard !parked, isShowing else { return }
        Log.state.info("collapse for lock/sleep")
        collapse()
    }

    @objc private func handleCommand(_ note: Notification) {
        guard !parked, let raw = note.object as? String else { return }
        Log.state.info("command \(raw, privacy: .public) from distributed notification")
        if raw.hasPrefix(ShelfCommand.pickWindowPrefix),
           let id = CGWindowID(raw.dropFirst(ShelfCommand.pickWindowPrefix.count)) {
            if let item = MenuBarItems.describe().first(where: { $0.item.id == id }) { openItem(item, interactive: false) }
            return
        }
        if raw.hasPrefix(ShelfCommand.assignPrefix) {
            // "assign:<key>=<section>" (move test harness): same path as the Settings picker.
            let body = raw.dropFirst(ShelfCommand.assignPrefix.count)
            if let eq = body.lastIndex(of: "="), let section = MenuSection(rawValue: String(body[body.index(after: eq)...])) {
                assign(String(body[..<eq]), to: section)
            }
            return
        }
        guard let command = ShelfCommand(rawValue: raw) else { return }
        if stateChangeBlocked {
            Log.state.info("command \(raw, privacy: .public) ignored: arranging")
            return
        }
        rehideTimer?.invalidate()
        notchBar.close()
        switch command {
        case .collapse: sections.apply(.collapsed, alwaysHiddenEnabled: settings.alwaysHiddenEnabled)
        case .showHidden: sections.apply(.showHidden, alwaysHiddenEnabled: settings.alwaysHiddenEnabled)
        case .showAll: sections.apply(.showAll, alwaysHiddenEnabled: settings.alwaysHiddenEnabled)
        }
    }

    // MARK: Hooks for ItemArranger

    var currentState: ShelfState { sections.state }
    var sectionFrames: (toggle: CGRect?, hidden: CGRect?, always: CGRect?) {
        (sections.toggleFrame, sections.hiddenDividerFrame, sections.alwaysHiddenDividerFrame)
    }

    func revealForArranging() {
        Log.state.info("showAll for arranging (was \(self.sections.state.rawValue, privacy: .public))")
        rehideTimer?.invalidate()
        notchBar.close()
        sections.apply(.showAll, alwaysHiddenEnabled: settings.alwaysHiddenEnabled)
    }

    /// Reveal for the Settings hover locator: no rehide timer while hovering.
    func revealForLocate(_ state: ShelfState) {
        guard !stateChangeBlocked else { return }
        rehideTimer?.invalidate()
        notchBar.close()
        sections.apply(state, alwaysHiddenEnabled: settings.alwaysHiddenEnabled)
    }

    /// Only called once the arrange lock has released.
    func restoreAfterArranging(_ state: ShelfState) {
        Log.state.info("restore after arranging -> \(state.rawValue, privacy: .public)")
        sections.apply(state, alwaysHiddenEnabled: settings.alwaysHiddenEnabled)
        if state != .collapsed { scheduleRehide() }
    }

    private func applySettings() {
        guard !parked else { return }
        tint?.applyIfChanged()
        sections.apply(sections.state, alwaysHiddenEnabled: settings.alwaysHiddenEnabled)
        if settings.hotKey != lastHotKey {
            lastHotKey = settings.hotKey
            let ok = hotKey.register(settings.hotKey)
            let error = ok ? nil : "macOS refused this shortcut. Another app may already use it."
            if settings.hotKeyError != error { settings.hotKeyError = error }
        }
        if settings.searchHotKey != lastSearchHotKey {
            lastSearchHotKey = settings.searchHotKey
            let ok = searchHotKey.register(settings.searchHotKey)
            let error = ok ? nil : "macOS refused this shortcut. Another app may already use it."
            if settings.searchHotKeyError != error { settings.searchHotKeyError = error }
        }
        if !settings.autoRehide { rehideTimer?.invalidate() }
        if !settings.rehideWhenLeaving { leaveWork?.cancel(); leaveWork = nil }
    }

    // MARK: Item search

    func openSearch() { search.open() }

    /// Reveals the item's section if needed, then presses it.
    func openItem(_ item: MenuBarItems.Described, interactive: Bool = true) {
        guard MenuBarItems.canPress, let element = item.element else {
            Log.arrange.info("search pick \(item.key, privacy: .public): no Accessibility or no AX element")
            if interactive { MenuBarItems.explainAccessibility(feature: "open menu bar items from search") }
            return
        }
        let section = currentSection(of: item.item)
        var delay = 0.0
        switch section {
        case .visible: break
        case .hidden:
            if sections.state == .collapsed { show(.showHidden); delay = 0.35 }
        case .alwaysHidden:
            if sections.state != .showAll { show(.showAll); delay = 0.35 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let ok = MenuBarItems.press(element: element)
            Log.arrange.info("search pick \(item.key, privacy: .public): section=\(section.rawValue, privacy: .public) pressed=\(ok, privacy: .public)")
            if !ok { NSSound.beep() }
        }
    }

    // MARK: State changes

    var isShowing: Bool { sections.state != .collapsed || notchBar.isVisible }

    func toggle() {
        Log.state.info("toggle (showing=\(self.isShowing, privacy: .public))")
        isShowing ? collapse() : show(.showHidden)
    }

    func show(_ state: ShelfState) {
        if stateChangeBlocked {
            Log.state.info("show \(state.rawValue, privacy: .public) blocked: arranging")
            return
        }
        Log.state.info("show \(state.rawValue, privacy: .public)")
        if state == .showHidden, showInNotchBarIfNeeded() {
            scheduleRehide()
            return
        }
        sections.apply(state, alwaysHiddenEnabled: settings.alwaysHiddenEnabled)
        scheduleRehide()
    }

    /// `force` only for switching the module off and quitting.
    func collapse(force: Bool = false) {
        guard !parked else { return }
        if !force, stateChangeBlocked {
            Log.state.info("collapse blocked: arranging")
            return
        }
        Log.state.info("collapse")
        rehideTimer?.invalidate()
        leaveWork?.cancel()
        leaveWork = nil
        notchBar.close()
        sections.apply(.collapsed, alwaysHiddenEnabled: settings.alwaysHiddenEnabled)
    }

    @objc private func toggleClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        Log.state.info("trigger: chevron click (flags=\(event?.modifierFlags.rawValue ?? 0, privacy: .public))")
        hoverGate.manualClick()
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else if event?.modifierFlags.contains(.option) == true {
            sections.state == .showAll ? collapse() : show(.showAll)
        } else {
            toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Search Menu Bar Items…", action: #selector(searchFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Show All Sections", action: #selector(showAllFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(settingsFromMenu), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Hub", action: #selector(quitFromMenu), keyEquivalent: "q").target = self
        guard let button = sections.toggleItem.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func showAllFromMenu() { show(.showAll) }
    @objc private func searchFromMenu() { openSearch() }
    @objc private func settingsFromMenu() { openSettings?() }
    @objc private func quitFromMenu() { quitApp?() }

    // MARK: Auto-rehide

    private func scheduleRehide(after seconds: TimeInterval? = nil) {
        rehideTimer?.invalidate()
        guard settings.autoRehide else { return }
        let delay = seconds ?? RehidePolicy.clamp(settings.rehideSeconds)
        rehideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.rehideTimerFired()
        }
    }

    private func rehideTimerFired() {
        if stateChangeBlocked {
            Log.state.info("rehide timer fired while arranging: wait 1 s")
            scheduleRehide(after: 1)
            return
        }
        let decision = RehidePolicy.decide(pointerInMenuBar: pointerInMenuBar(NSEvent.mouseLocation),
                                           menuOpen: MenuBarItems.isMenuOpen())
        Log.state.info("rehide timer fired: \(String(describing: decision), privacy: .public)")
        switch decision {
        case .rehide: collapse()
        case .wait(let seconds): scheduleRehide(after: seconds)
        }
    }

    // MARK: Triggers (click, hover, scroll)

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .mouseMoved, .scrollWheel]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] in self?.handle($0) }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] in self?.handle($0); return $0 }) {
            monitors.append(local)
        }
    }

    private func handle(_ event: NSEvent) {
        let point = NSEvent.mouseLocation
        switch event.type {
        case .leftMouseDown:
            // ⌘-drag rearranges items; never treat it as a click.
            guard !event.modifierFlags.contains(.command), let strip = menuBarStrip(containing: point),
                  let chevron = sections.toggleFrame else { return }
            let action = MenuBarGeometry.clickAction(
                at: point, chevron: chevron, strip: strip, statusItemFrames: MenuBarItems.all().map(\.frame),
                appMenuMaxX: strip.midX, emptyAreaEnabled: settings.showOnClick)
            // .chevron is handled by the chevron button's own action.
            guard action == .emptyArea else { return }
            Log.state.info("trigger: empty menu bar click at x=\(Int(point.x), privacy: .public)")
            toggle()
        case .mouseMoved:
            let inZone = sections.toggleFrame.map {
                CGRect(x: $0.minX - 80, y: $0.minY - 2, width: $0.width + 80, height: $0.height + 4).contains(point)
            } ?? false
            // Always fed, so the click lockout clears once the pointer leaves the zone.
            let reveal = hoverGate.pointerMoved(inZone: inZone, isShowing: isShowing)
            if isShowing {
                scheduleLeaveRehide(point)
                return
            }
            if settings.showOnHoverNearChevron, reveal {
                Log.state.info("trigger: hover near chevron")
                show(.showHidden)
                return
            }
            guard settings.showOnHover else { return }
            if pointerInMenuBar(point) {
                guard hoverTimer == nil else { return }
                hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                    guard let self else { return }
                    self.hoverTimer = nil
                    if self.isEmptyMenuBarPoint(NSEvent.mouseLocation) {
                        Log.state.info("trigger: hover")
                        self.show(.showHidden)
                    }
                }
            } else {
                hoverTimer?.invalidate()
                hoverTimer = nil
            }
        case .scrollWheel:
            guard settings.showOnScroll, pointerInMenuBar(point),
                  abs(event.scrollingDeltaY) > 0.5, Date().timeIntervalSince(lastScroll) > 0.4 else { return }
            lastScroll = Date()
            Log.state.info("trigger: scroll dy=\(event.scrollingDeltaY, privacy: .public)")
            if event.scrollingDeltaY > 0 {
                if !isShowing { show(.showHidden) }
            } else if isShowing {
                collapse()
            }
        default:
            break
        }
    }

    /// From Awning: with "rehide when leaving", collapse 1 s after the pointer leaves the menu bar.
    private func scheduleLeaveRehide(_ point: CGPoint) {
        guard settings.rehideWhenLeaving else { return }
        if pointerInMenuBar(point) {
            leaveWork?.cancel()
            leaveWork = nil
            return
        }
        guard leaveWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.leaveWork = nil
            if !self.stateChangeBlocked, !self.pointerInMenuBar(NSEvent.mouseLocation), !MenuBarItems.isMenuOpen() {
                Log.state.info("rehide: pointer left the menu bar")
                self.collapse()
            }
        }
        leaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func menuBarStrip(containing point: CGPoint) -> CGRect? {
        guard let screen = NSScreen.screens.first(where: {
            point.x >= $0.frame.minX && point.x < $0.frame.maxX && point.y >= $0.frame.minY && point.y <= $0.frame.maxY
        }) else { return nil }
        let thickness = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
        return MenuBarGeometry.menuBarStrip(screenFrame: screen.frame, thickness: thickness)
    }

    private func pointerInMenuBar(_ point: CGPoint) -> Bool {
        guard let strip = menuBarStrip(containing: point) else { return false }
        return point.y >= strip.minY && point.y <= strip.maxY
    }

    private func isEmptyMenuBarPoint(_ point: CGPoint) -> Bool {
        guard let strip = menuBarStrip(containing: point) else { return false }
        // Hover never fires beside the chevron, where the collapsed divider sits.
        if let chevron = sections.toggleFrame, MenuBarGeometry.isNearChevron(point, chevron: chevron) { return false }
        var frames = MenuBarItems.all().map(\.frame)
        if let toggle = sections.toggleFrame { frames.append(toggle) }
        // App menu width is unknown without Accessibility: treat the left half as app menus.
        return MenuBarGeometry.isEmptyMenuBarPoint(point, strip: strip, statusItemFrames: frames, appMenuMaxX: strip.midX)
    }

    // MARK: Notch bar

    /// On a notched screen, if revealing the hidden section would push items
    /// behind the notch, shows them in a bar below the menu bar instead.
    private func showInNotchBarIfNeeded() -> Bool {
        guard settings.useBarOnNotch, let screen = sections.screen,
              NotchLayout.notchRect(screen.shelfInfo) != nil,
              let divider = sections.hiddenDividerFrame else { return false }
        let always = sections.alwaysHiddenDividerFrame
        let hiddenItems = MenuBarItems.all().filter {
            SectionLayout.section(itemFrame: $0.frame, hiddenDivider: divider, alwaysHiddenDivider: always) == .hidden
        }
        let width = hiddenItems.reduce(0) { $0 + $1.frame.width }
        guard NotchLayout.shouldUseBar(screen: screen.shelfInfo, visibleSectionMinX: divider.maxX, hiddenItemsWidth: width) else {
            return false
        }
        notchBar.show(items: hiddenItems, screen: screen, rightEdge: divider.maxX) { [weak self] item in
            let element = MenuBarItems.describe().first { $0.item.id == item.id }?.element
            if !(element.map { MenuBarItems.press(element: $0) } ?? false) {
                if !MenuBarItems.canPress { MenuBarItems.explainAccessibility(feature: "open items from the Shelf bar") }
            }
            self?.rehideTimer?.invalidate()
        }
        return true
    }
}
