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
        let restore = currentState
        revealForArranging()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.performMoves(pending, restore: restore)
        }
    }

    private func performMoves(_ moves: [(String, MenuSection)], restore: ShelfState) {
        guard let (key, target) = moves.first else {
            restoreAfterArranging(restore)
            itemList.busy = false
            refreshItemList()
            return
        }
        let rest = Array(moves.dropFirst())
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        guard let item = keyedItems().first(where: { $0.key == key })?.item,
              let hidden = sectionFrames.hidden,
              let toggle = sectionFrames.toggle,
              // cocoaRect(fromCG:) is its own inverse, so it also maps Cocoa to CG.
              let drop = DropPlan.dropPoint(
                  for: target,
                  toggle: MenuBarGeometry.cocoaRect(fromCG: toggle, primaryScreenHeight: primaryHeight),
                  hiddenDivider: MenuBarGeometry.cocoaRect(fromCG: hidden, primaryScreenHeight: primaryHeight),
                  alwaysHiddenDivider: sectionFrames.always.map { MenuBarGeometry.cocoaRect(fromCG: $0, primaryScreenHeight: primaryHeight) })
        else {
            performMoves(rest, restore: restore)
            return
        }
        let start = CGPoint(x: item.cgFrame.midX, y: item.cgFrame.midY)
        let before = currentSection(of: item)
        Log.arrange.info("move \(key, privacy: .public): before=\(before.rawValue, privacy: .public) target=\(target.rawValue, privacy: .public) start=(\(Int(start.x), privacy: .public),\(Int(start.y), privacy: .public)) drop=(\(Int(drop.x), privacy: .public),\(Int(drop.y), privacy: .public)) chevron=\(Int(toggle.minX), privacy: .public)..\(Int(toggle.maxX), privacy: .public)")
        let windowID = item.id
        for delay in [0.2, 1.0, 3.0] {
            // Sampled from the end of the drag (the drag itself takes about 1.2 s).
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2 + delay) {
                let now = MenuBarItems.all().first { $0.id == windowID }
                let chevron = self.sectionFrames.toggle
                Log.arrange.info("move \(key, privacy: .public) +\(delay, privacy: .public)s: x=\(now.map { Int($0.frame.minX) } ?? -1, privacy: .public) chevron=\(chevron.map { Int($0.minX) } ?? -1, privacy: .public) section=\(now.map { self.currentSection(of: $0).rawValue } ?? "gone", privacy: .public) state=\(self.currentState.rawValue, privacy: .public)")
            }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            CommandDrag.perform(from: start, to: drop)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.performMoves(rest, restore: restore)
            }
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
