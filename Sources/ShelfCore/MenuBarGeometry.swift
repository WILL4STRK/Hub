import CoreGraphics

public enum MenuBarGeometry {
    /// Converts a Core Graphics window rect (top-left origin of the primary
    /// screen) into Cocoa coordinates (bottom-left origin).
    public static func cocoaRect(fromCG rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenHeight - rect.minY - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    /// True for a real menu bar item window: it starts at the top edge of a
    /// screen and is no taller than the menu bar. Filters out status-level
    /// panels such as Cloudflare WARP's offscreen dropdown (358x453 at y=24).
    /// `screenTopsCG` are the CG y values of each screen's top edge.
    public static func isMenuBarItemWindow(cgFrame: CGRect, screenTopsCG: [CGFloat], maxHeight: CGFloat) -> Bool {
        guard cgFrame.width > 0, cgFrame.height > 0, cgFrame.height <= maxHeight else { return false }
        return screenTopsCG.contains { abs(cgFrame.minY - $0) <= 1 }
    }

    public enum ClickAction: Equatable {
        /// On the chevron itself: its button handles the toggle.
        case chevron
        /// A genuinely empty menu bar area (only when that option is on).
        case emptyArea
        case none
    }

    /// Clicks this close to the chevron's left edge never count as empty-area clicks.
    /// When collapsed, Shelf's wide hidden divider fills exactly this region.
    public static let chevronGuard: CGFloat = 40

    /// Routes a mouse-down in the menu bar. Only the chevron's own frame
    /// toggles by default. Empty-area clicks require `emptyAreaEnabled` and
    /// exclude the guard strip beside the chevron.
    public static func clickAction(
        at point: CGPoint,
        chevron: CGRect,
        strip: CGRect,
        statusItemFrames: [CGRect],
        appMenuMaxX: CGFloat,
        emptyAreaEnabled: Bool
    ) -> ClickAction {
        let inStripY = point.y >= strip.minY && point.y <= strip.maxY
        if inStripY, point.x >= chevron.minX, point.x < chevron.maxX { return .chevron }
        guard emptyAreaEnabled, !isNearChevron(point, chevron: chevron) else { return .none }
        return isEmptyMenuBarPoint(point, strip: strip, statusItemFrames: statusItemFrames, appMenuMaxX: appMenuMaxX)
            ? .emptyArea : .none
    }

    /// True inside the guard strip left of the chevron (or on the chevron).
    public static func isNearChevron(_ point: CGPoint, chevron: CGRect) -> Bool {
        point.x >= chevron.minX - chevronGuard && point.x < chevron.maxX
    }

    /// Menu bar strip for a screen frame (Cocoa coordinates).
    public static func menuBarStrip(screenFrame: CGRect, thickness: CGFloat) -> CGRect {
        CGRect(x: screenFrame.minX, y: screenFrame.maxY - thickness, width: screenFrame.width, height: thickness)
    }

    /// True when `point` is in the menu bar, right of the app menus and not on a
    /// status item. App menu width is unknown without Accessibility, so callers pass
    /// an estimate for `appMenuMaxX`.
    public static func isEmptyMenuBarPoint(
        _ point: CGPoint,
        strip: CGRect,
        statusItemFrames: [CGRect],
        appMenuMaxX: CGFloat
    ) -> Bool {
        // Include the top edge: the pointer rests at maxY when pushed against it.
        guard point.x >= strip.minX, point.x < strip.maxX,
              point.y >= strip.minY, point.y <= strip.maxY else { return false }
        if point.x <= appMenuMaxX { return false }
        return !statusItemFrames.contains { frame in
            point.x >= frame.minX && point.x < frame.maxX
        }
    }
}
