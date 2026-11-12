import Combine
import Foundation
import ShelfCore

/// User preferences, persisted in UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    @Published var showOnClick: Bool { didSet { defaults.set(showOnClick, forKey: Keys.showOnClick) } }
    @Published var showOnHover: Bool { didSet { defaults.set(showOnHover, forKey: Keys.showOnHover) } }
    @Published var showOnScroll: Bool { didSet { defaults.set(showOnScroll, forKey: Keys.showOnScroll) } }
    @Published var hotKey: HotKeySpec? { didSet { saveHotKey() } }
    @Published var autoRehide: Bool { didSet { defaults.set(autoRehide, forKey: Keys.autoRehide) } }
    @Published var rehideSeconds: Double {
        didSet { defaults.set(RehidePolicy.clamp(rehideSeconds), forKey: Keys.rehideSeconds) }
    }
    @Published var alwaysHiddenEnabled: Bool {
        didSet { defaults.set(alwaysHiddenEnabled, forKey: Keys.alwaysHidden) }
    }
    @Published var useBarOnNotch: Bool { didSet { defaults.set(useBarOnNotch, forKey: Keys.useBarOnNotch) } }
    /// Not persisted: set when macOS refuses the chosen shortcut.
    @Published var hotKeyError: String?
    /// Format of the itemSections keys (ItemIdentity.keysVersion). 1 = "bundleID#index".
    @Published var itemKeysVersion: Int { didSet { defaults.set(itemKeysVersion, forKey: Keys.itemKeysVersion) } }
    /// Global shortcut for the item search popup.
    @Published var searchHotKey: HotKeySpec? { didSet { saveHotKey(searchHotKey, key: Keys.searchHotKey) } }
    /// Not persisted: set when macOS refuses the search shortcut.
    @Published var searchHotKeyError: String?
    // From Awning's menu-bar hider
    /// Reveal when the pointer is within 80 pt left of the chevron.
    @Published var showOnHoverNearChevron: Bool { didSet { defaults.set(showOnHoverNearChevron, forKey: Keys.showOnHoverNearChevron) } }
    /// Also rehide 1 s after the pointer leaves the menu bar (no menu open).
    @Published var rehideWhenLeaving: Bool { didSet { defaults.set(rehideWhenLeaving, forKey: Keys.rehideWhenLeaving) } }
    @Published var menuBarTint: Bool { didSet { defaults.set(menuBarTint, forKey: Keys.menuBarTint) } }
    @Published var menuBarTintColor: String { didSet { defaults.set(menuBarTintColor, forKey: Keys.menuBarTintColor) } }

    /// Saved per-item sections, keyed by ItemIdentity v2 keys.
    @Published var itemSections: [String: MenuSection] {
        didSet {
            if let data = try? JSONEncoder().encode(itemSections) { defaults.set(data, forKey: Keys.itemSections) }
        }
    }

    private enum Keys {
        static let showOnClick = "showOnClick"
        static let showOnHover = "showOnHover"
        static let showOnScroll = "showOnScroll"
        static let hotKey = "hotKey"
        static let autoRehide = "autoRehide"
        static let rehideSeconds = "rehideSeconds"
        static let alwaysHidden = "alwaysHiddenEnabled"
        static let useBarOnNotch = "useBarOnNotch"
        static let itemSections = "itemSections"
        static let itemKeysVersion = "itemKeysVersion"
        static let searchHotKey = "searchHotKey"
        static let showOnHoverNearChevron = "showOnHoverNearChevron"
        static let rehideWhenLeaving = "rehideWhenLeaving"
        // Same key names as Awning, so the migration copies them unchanged.
        static let menuBarTint = "menuBarTint"
        static let menuBarTintColor = "menuBarTintColor"
    }

    private init() {
        defaults.register(defaults: [
            // Off by default: only the chevron itself toggles.
            Keys.showOnClick: false,
            Keys.showOnHover: false,
            Keys.showOnScroll: false,
            Keys.autoRehide: true,
            Keys.rehideSeconds: 10.0,
            Keys.alwaysHidden: true,
            Keys.useBarOnNotch: true,
            Keys.itemKeysVersion: 1,
            Keys.showOnHoverNearChevron: false,
            Keys.rehideWhenLeaving: false,
            Keys.menuBarTint: false,
            Keys.menuBarTintColor: "#5E5CE6",
        ])
        showOnClick = defaults.bool(forKey: Keys.showOnClick)
        showOnHover = defaults.bool(forKey: Keys.showOnHover)
        showOnScroll = defaults.bool(forKey: Keys.showOnScroll)
        autoRehide = defaults.bool(forKey: Keys.autoRehide)
        rehideSeconds = RehidePolicy.clamp(defaults.double(forKey: Keys.rehideSeconds))
        alwaysHiddenEnabled = defaults.bool(forKey: Keys.alwaysHidden)
        useBarOnNotch = defaults.bool(forKey: Keys.useBarOnNotch)
        hotKey = defaults.data(forKey: Keys.hotKey).flatMap { try? JSONDecoder().decode(HotKeySpec.self, from: $0) }
        searchHotKey = defaults.data(forKey: Keys.searchHotKey).flatMap { try? JSONDecoder().decode(HotKeySpec.self, from: $0) }
        itemKeysVersion = defaults.integer(forKey: Keys.itemKeysVersion)
        showOnHoverNearChevron = defaults.bool(forKey: Keys.showOnHoverNearChevron)
        rehideWhenLeaving = defaults.bool(forKey: Keys.rehideWhenLeaving)
        menuBarTint = defaults.bool(forKey: Keys.menuBarTint)
        menuBarTintColor = defaults.string(forKey: Keys.menuBarTintColor) ?? "#5E5CE6"
        itemSections = defaults.data(forKey: Keys.itemSections)
            .flatMap { try? JSONDecoder().decode([String: MenuSection].self, from: $0) } ?? [:]
    }

    private func saveHotKey() { saveHotKey(hotKey, key: Keys.hotKey) }

    private func saveHotKey(_ spec: HotKeySpec?, key: String) {
        if let spec, let data = try? JSONEncoder().encode(spec) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
