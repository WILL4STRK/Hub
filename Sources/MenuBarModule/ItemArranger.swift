import AppKit
import ApplicationServices
import ShelfCore
import os

struct ItemRow: Identifiable {
    let id: String // ItemIdentity v2 key
    let name: String
    let detail: String?
    let icon: NSImage?
    let section: MenuSection
}

final class ItemListModel: ObservableObject {
    @Published var rows: [ItemRow] = []
    @Published var needsAccessibility = false
    @Published var busy = false
    /// Last move that failed, shown in Settings; nil after a clean run.
    @Published var lastError: String?
}

/// Moves other apps' status items between sections with a posted ⌘-drag.
/// Needs Accessibility for Shelf. Without it, nothing is moved and the
/// Settings list explains why. It never shows the system permission prompt.
extension ShelfController {
    /// Current items keyed by ItemIdentity v2 keys.
    func keyedItems() -> [(key: String, item: MenuBarItem)] {
        MenuBarItems.describe().map { (key: $0.key, item: $0.item) }
    }

    /// One-time migration of saved choices from v1 keys ("owner#index").
    /// Runs only with Accessibility, since v2 keys need AX identifiers.
    func migrateItemKeysIfNeeded() {
        guard settings.itemKeysVersion < ItemIdentity.keysVersion else { return }
        guard AXIsProcessTrusted() else {
            Log.arrange.info("key migration: waiting for Accessibility")
            return
        }
        let described = MenuBarItems.describe()
        let migration = ItemIdentity.migrate(saved: settings.itemSections,
                                             legacyKeys: MenuBarItems.legacyKeys(described),
                                             newKeys: described.map(\.key))
        for m in migration.mapping {
            Log.arrange.info("key migration: \(m.old, privacy: .public) -> \(m.new ?? "dropped", privacy: .public) (\(m.section.rawValue, privacy: .public))")
        }
        settings.itemSections = migration.saved
        settings.itemKeysVersion = ItemIdentity.keysVersion
    }

    func currentSection(of item: MenuBarItem) -> MenuSection {
        guard let hidden = sectionFrames.hidden else { return .visible }
        return SectionLayout.section(itemFrame: item.frame, hiddenDivider: hidden,
                                     alwaysHiddenDivider: sectionFrames.always, toggle: sectionFrames.toggle)
    }

    func refreshItemList() {
        itemList.needsAccessibility = !AXIsProcessTrusted()
        Log.arrange.info("refresh item list (trusted=\(!self.itemList.needsAccessibility, privacy: .public))")
        itemList.rows = MenuBarItems.describe().map { d in
            ItemRow(id: d.key, name: d.name, detail: d.name == d.appName ? nil : d.appName,
                    icon: d.icon, section: currentSection(of: d.item))
        }
    }

    /// Saves the choice and moves the item now if Shelf has Accessibility.
    func assign(_ key: String, to section: MenuSection) {
        Log.arrange.info("settings picker: \(key, privacy: .public) -> \(section.rawValue, privacy: .public)")
        settings.itemSections[key] = section
        applyAssignments(only: [key], reason: "settings picker")
    }

    /// Moves every item whose saved section differs from where it is now.
    func applyAssignments(only keys: Set<String>? = nil, reason: String) {
        guard AXIsProcessTrusted() else {
            Log.arrange.info("apply (\(reason, privacy: .public)): skipped, Accessibility not trusted")
            itemList.needsAccessibility = true
            return
        }
        let pending = keyedItems().compactMap { entry -> (String, MenuSection)? in
            guard keys?.contains(entry.key) ?? true, let wanted = settings.itemSections[entry.key] else { return nil }
            let now = currentSection(of: entry.item)
            let f = entry.item.cgFrame
            Log.arrange.info("apply (\(reason, privacy: .public)): \(entry.key, privacy: .public) frame=\(Int(f.minX), privacy: .public)..\(Int(f.maxX), privacy: .public) y=\(Int(f.minY), privacy: .public) h=\(Int(f.height), privacy: .public) now=\(now.rawValue, privacy: .public) wanted=\(wanted.rawValue, privacy: .public)")
            return wanted == now ? nil : (entry.key, wanted)
        }
        Log.arrange.info("apply (\(reason, privacy: .public)): \(pending.count, privacy: .public) pending, busy=\(self.itemList.busy, privacy: .public)")
        guard !pending.isEmpty, !itemList.busy else { return }
        if pending.contains(where: { $0.1 == .alwaysHidden }) && !settings.alwaysHiddenEnabled { return }
        itemList.busy = true
        itemList.lastError = nil
        arrangeLock.beginSession()
        let restore = currentState
        revealForArranging()
        performMoves(pending, restore: restore, errors: [])
    }

    /// One move at a time: reveal, wait until the item is on screen, re-read its frame, drag with the
    /// arrange lock held, settle, verify the section, retry once, then report.
    private func performMoves(_ moves: [(String, MenuSection)], restore: ShelfState, errors: [String], attempt: Int = 1) {
        guard let (key, target) = moves.first else {
            finishArranging(restore: restore, errors: errors)
            return
        }
        let rest = Array(moves.dropFirst())
        func next(_ error: String? = nil) {
            if let error {
                Log.arrange.error("move \(key, privacy: .public): \(error, privacy: .public)")
                Log.arrange.info("move result \(key, privacy: .public) target=\(target.rawValue, privacy: .public) FAIL attempts=\(attempt, privacy: .public)")
            }
            performMoves(rest, restore: restore, errors: errors + (error.map { [$0] } ?? []))
        }
        // The sections must be expanded before the frame is read (a collapsed item sits at x about -3800).
        if currentState != .showAll { revealForArranging() }
        guard let windowID = keyedItems().first(where: { $0.key == key })?.item.id else {
            next("item not found in the menu bar")
            return
        }
        // Wait until both the item and the drop point (which comes from the divider frames) are on screen:
        // right after expanding, the dividers can still report their collapsed frames (x about -3800).
        waitUntilReady(windowID, target: target, deadline: Date().addingTimeInterval(3)) { [weak self] ready in
            guard let self else { return }
            guard let (item, drop) = ready else {
                next("item or drop point still off screen after 3 s with the sections expanded; nothing was moved")
                return
            }
            let start = CGPoint(x: item.cgFrame.midX, y: item.cgFrame.midY)
            let before = self.currentSection(of: item)
            Log.arrange.info("move \(key, privacy: .public) attempt \(attempt, privacy: .public): before=\(before.rawValue, privacy: .public) target=\(target.rawValue, privacy: .public) start=(\(Int(start.x), privacy: .public),\(Int(start.y), privacy: .public)) drop=(\(Int(drop.x), privacy: .public),\(Int(drop.y), privacy: .public)) state=\(self.currentState.rawValue, privacy: .public)")
            self.arrangeLock.beginDrag()
            DispatchQueue.global(qos: .userInitiated).async {
                CommandDrag.perform(from: start, to: drop)
                DispatchQueue.main.async {
                    self.arrangeLock.endDrag(at: Date())
                    // Verify once the settle delay is over and macOS has placed the item.
                    DispatchQueue.main.asyncAfter(deadline: .now() + ArrangeLock.settle) {
                        let now = MenuBarItems.all().first { $0.id == windowID }
                        let landedIn = now.map { self.currentSection(of: $0) }
                        let landed = landedIn == target
                        Log.arrange.info("move \(key, privacy: .public) attempt \(attempt, privacy: .public) check: x=\(now.map { Int($0.frame.minX) } ?? -1, privacy: .public) section=\(landedIn?.rawValue ?? "gone", privacy: .public) state=\(self.currentState.rawValue, privacy: .public)")
                        switch MoveCheck.outcome(landed: landed, attempt: attempt) {
                        case .done:
                            Log.arrange.info("move result \(key, privacy: .public) target=\(target.rawValue, privacy: .public) PASS attempts=\(attempt, privacy: .public)")
                            self.performMoves(rest, restore: restore, errors: errors)
                        case .retry:
                            self.performMoves(moves, restore: restore, errors: errors, attempt: attempt + 1)
                        case .failed:
                            next("did not reach \(target.rawValue) after \(attempt) tries (now \(landedIn?.rawValue ?? "gone"))")
                        }
                    }
                }
            }
        }
    }

    /// Fresh item frame and drop point, or nil while either is off screen.
    private func readyMove(_ id: CGWindowID, target: MenuSection) -> (MenuBarItem, CGPoint)? {
        let screens = NSScreen.screens.map(\.frame)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        guard let item = MenuBarItems.all().first(where: { $0.id == id }),
              MoveCheck.isOnScreen(item.frame, screens: screens),
              let hidden = sectionFrames.hidden, let toggle = sectionFrames.toggle,
              // cocoaRect(fromCG:) is its own inverse, so it also maps Cocoa to CG.
              let drop = DropPlan.dropPoint(
                  for: target,
                  toggle: MenuBarGeometry.cocoaRect(fromCG: toggle, primaryScreenHeight: primaryHeight),
                  hiddenDivider: MenuBarGeometry.cocoaRect(fromCG: hidden, primaryScreenHeight: primaryHeight),
                  alwaysHiddenDivider: sectionFrames.always.map { MenuBarGeometry.cocoaRect(fromCG: $0, primaryScreenHeight: primaryHeight) })
        else { return nil }
        let dropCocoa = MenuBarGeometry.cocoaRect(fromCG: CGRect(x: drop.x, y: drop.y, width: 1, height: 1), primaryScreenHeight: primaryHeight)
        return MoveCheck.isOnScreen(dropCocoa, screens: screens) ? (item, drop) : nil
    }

    /// Polls every 0.1 s until readyMove succeeds (nil on timeout).
    private func waitUntilReady(_ id: CGWindowID, target: MenuSection, deadline: Date,
                                then: @escaping ((MenuBarItem, CGPoint)?) -> Void) {
        if let ready = readyMove(id, target: target) {
            then(ready)
            return
        }
        guard Date() < deadline else {
            then(nil)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.waitUntilReady(id, target: target, deadline: deadline, then: then)
        }
    }

    private func finishArranging(restore: ShelfState, errors: [String]) {
        arrangeLock.endSession()
        // Restore only once the last drag's settle delay is over.
        let wait = max(0, ArrangeLock.settle)
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            self.restoreAfterArranging(restore)
            self.itemList.busy = false
            if !errors.isEmpty {
                self.itemList.lastError = errors.count == 1 ? "Move failed: \(errors[0])" : "\(errors.count) moves failed: \(errors.joined(separator: "; "))"
                NSSound.beep()
            }
            self.refreshItemList()
        }
    }
}

/// Read-only preview of migrateItemKeysIfNeeded(), using the same ShelfCore logic.
enum KeyMigrationDryRun {
    static func run() {
        let defaults = UserDefaults.standard
        let saved = defaults.data(forKey: "itemSections")
            .flatMap { try? JSONDecoder().decode([String: MenuSection].self, from: $0) } ?? [:]
        print("Accessibility trusted: \(AXIsProcessTrusted() ? "yes" : "no"), saved keys version: \(max(defaults.integer(forKey: "itemKeysVersion"), 1))")
        let described = MenuBarItems.describe()
        let legacy = MenuBarItems.legacyKeys(described)
        print("Current items (v1 key -> v2 key):")
        for (d, old) in zip(described, legacy) {
            print("  \(old)  ->  \(d.key)   [\(d.name) / \(d.appName), x=\(Int(d.item.frame.minX))]")
        }
        let migration = ItemIdentity.migrate(saved: saved, legacyKeys: legacy, newKeys: described.map(\.key))
        print("Saved choices to migrate:")
        for m in migration.mapping {
            print("  \(m.old) = \(m.section.rawValue)  ->  \(m.new ?? "DROPPED (no current item)")")
        }
    }
}
