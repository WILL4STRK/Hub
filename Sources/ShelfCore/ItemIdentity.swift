import CoreGraphics
import Foundation

/// One menu bar item as seen by Shelf: owner bundle ID (or name), left edge,
/// and the Accessibility identifier/title when the item exposes them.
public struct ItemIdentityInput: Equatable {
    public var owner: String
    public var minX: CGFloat
    public var identifier: String?
    public var title: String?

    public init(owner: String, minX: CGFloat, identifier: String? = nil, title: String? = nil) {
        self.owner = owner
        self.minX = minX
        self.identifier = identifier
        self.title = title
    }
}

/// Saved-choice keys that survive reordering. Preference:
///   1. "owner|id:<AXIdentifier>"   (Control Center: com.apple.menuextra.sound, ...)
///   2. "owner|title:<AXTitle>"     (Spotlight, Siri)
///   3. "owner#<n>"                 position among the owner's items without 1 or 2
/// AXDescription is not used: it changes with state ("Wi-Fi, connected, 3 bars").
/// Identical keys within one owner get a "#k" suffix, k >= 1, in left-to-right order.
public enum ItemIdentity {
    public static let keysVersion = 2

    public static func keys(_ items: [ItemIdentityInput]) -> [String] {
        let order = items.indices.sorted { items[$0].minX < items[$1].minX }
        var positional: [String: Int] = [:]
        var seen: [String: Int] = [:]
        var result = Array(repeating: "", count: items.count)
        for i in order {
            let item = items[i]
            let base: String
            if let id = item.identifier, !id.isEmpty {
                base = "\(item.owner)|id:\(id)"
            } else if let title = item.title, !title.isEmpty {
                base = "\(item.owner)|title:\(title)"
            } else {
                let n = positional[item.owner, default: 0]
                positional[item.owner] = n + 1
                base = "\(item.owner)#\(n)"
            }
            let dup = seen[base, default: 0]
            seen[base] = dup + 1
            result[i] = dup == 0 ? base : "\(base)#\(dup)"
        }
        return result
    }

    /// Index of the Accessibility element whose left edge lies inside the
    /// window's horizontal span (closest wins). nil means the window has no
    /// element, such as Control Center's hidden extra window.
    public static func axMatch(windowMinX: CGFloat, windowMaxX: CGFloat, axXs: [CGFloat]) -> Int? {
        let candidates = axXs.indices.filter { axXs[$0] >= windowMinX - 2 && axXs[$0] < windowMaxX }
        return candidates.min { abs(axXs[$0] - windowMinX) < abs(axXs[$1] - windowMinX) }
    }

    public struct Migration: Equatable {
        public var saved: [String: MenuSection]
        /// (old key, new key or nil when no current item has that old key)
        public var mapping: [Mapping]
    }

    public struct Mapping: Equatable {
        public var old: String
        public var new: String?
        public var section: MenuSection

        public init(old: String, new: String?, section: MenuSection) {
            self.old = old
            self.new = new
            self.section = section
        }
    }

    /// Maps saved choices from version-1 keys (ItemKey: "owner#index") to
    /// version-2 keys. `legacyKeys[i]` and `newKeys[i]` describe the same
    /// current item. Old keys with no current item are dropped.
    public static func migrate(saved: [String: MenuSection], legacyKeys: [String], newKeys: [String]) -> Migration {
        precondition(legacyKeys.count == newKeys.count)
        let lookup = Dictionary(zip(legacyKeys, newKeys), uniquingKeysWith: { first, _ in first })
        var result: [String: MenuSection] = [:]
        var mapping: [Mapping] = []
        for (old, section) in saved.sorted(by: { $0.key < $1.key }) {
            let new = lookup[old]
            if let new { result[new] = section }
            mapping.append(Mapping(old: old, new: new, section: section))
        }
        return Migration(saved: result, mapping: mapping)
    }
}

/// Ranking for the item search popup. Case- and diacritic-insensitive.
/// Higher is better; nil means no match. An empty query matches everything.
public enum SearchRank {
    public static func score(query: String, fields: [String]) -> Int? {
        let q = query.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard !q.isEmpty else { return 0 }
        var best: Int?
        for (i, field) in fields.enumerated() {
            let f = field.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            let weight = max(0, 10 - i) // earlier fields (app name) weigh more
            let s: Int?
            if f == q { s = 300 + weight }
            else if f.hasPrefix(q) { s = 200 + weight }
            else if f.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(q) }) { s = 150 + weight }
            else if f.contains(q) { s = 100 + weight }
            else { s = nil }
            if let s, s > (best ?? -1) { best = s }
        }
        return best
    }
}
