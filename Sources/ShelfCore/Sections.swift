import CoreGraphics

/// What the menu bar currently reveals.
public enum ShelfState: String, Codable, CaseIterable {
    /// Hidden and always-hidden sections are pushed offscreen.
    case collapsed
    /// Hidden section revealed, always-hidden section still offscreen.
    case showHidden
    /// Everything revealed, including the always-hidden section.
    case showAll
}

/// Which section a menu bar item belongs to, based on divider positions.
public enum MenuSection: String, Codable, CaseIterable {
    case visible, hidden, alwaysHidden
}

public struct DividerLengths: Equatable {
    public let hidden: CGFloat
    public let alwaysHidden: CGFloat
}

/// Divider-expansion technique: a divider status item grows to a huge length,
/// which pushes every status item to its left off the screen.
public enum SectionLayout {
    /// Length that pushes everything to the left of a divider offscreen.
    public static let expandedLength: CGFloat = 10_000
    /// Length of a divider when its section is revealed.
    public static let dividerLength: CGFloat = 14

    public static func lengths(for state: ShelfState) -> DividerLengths {
        switch state {
        case .collapsed:
            return DividerLengths(hidden: expandedLength, alwaysHidden: expandedLength)
        case .showHidden:
            return DividerLengths(hidden: dividerLength, alwaysHidden: expandedLength)
        case .showAll:
            return DividerLengths(hidden: dividerLength, alwaysHidden: dividerLength)
        }
    }

    /// Next state for a plain toggle (click, hotkey, hover). Leaving any expanded
    /// state collapses; collapsed reveals the hidden section.
    public static func toggled(_ state: ShelfState) -> ShelfState {
        state == .collapsed ? .showHidden : .collapsed
    }

    /// Classifies an item by horizontal position. Frames share one coordinate
    /// space; items fully left of a divider's left edge belong to that divider's section.
    /// When `toggle` is given, only items right of the chevron count as visible;
    /// a stray item between the hidden divider and the chevron counts as hidden.
    public static func section(
        itemFrame: CGRect,
        hiddenDivider: CGRect,
        alwaysHiddenDivider: CGRect?,
        toggle: CGRect? = nil
    ) -> MenuSection {
        let tolerance: CGFloat = 1
        if let always = alwaysHiddenDivider, itemFrame.maxX <= always.minX + tolerance {
            return .alwaysHidden
        }
        if itemFrame.maxX <= hiddenDivider.minX + tolerance {
            return .hidden
        }
        if let toggle, itemFrame.maxX <= toggle.minX + tolerance {
            return .hidden
        }
        return .visible
    }
}
