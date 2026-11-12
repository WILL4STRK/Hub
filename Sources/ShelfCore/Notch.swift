import CoreGraphics

/// Screen values needed for notch decisions, so they can be faked in checks.
public struct ScreenInfo: Equatable {
    public var frame: CGRect
    public var safeAreaTop: CGFloat
    public var auxiliaryTopLeft: CGRect?
    public var auxiliaryTopRight: CGRect?

    public init(frame: CGRect, safeAreaTop: CGFloat, auxiliaryTopLeft: CGRect?, auxiliaryTopRight: CGRect?) {
        self.frame = frame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeft = auxiliaryTopLeft
        self.auxiliaryTopRight = auxiliaryTopRight
    }
}

public enum NotchLayout {
    /// The notch is the gap between the two auxiliary top areas.
    public static func notchRect(_ screen: ScreenInfo) -> CGRect? {
        guard screen.safeAreaTop > 0,
              let left = screen.auxiliaryTopLeft,
              let right = screen.auxiliaryTopRight,
              right.minX > left.maxX else { return nil }
        return CGRect(x: left.maxX, y: left.minY, width: right.minX - left.maxX, height: left.height)
    }

    /// True when revealing `hiddenItemsWidth` points of items to the left of
    /// `visibleSectionMinX` would push items into or past the notch.
    public static func shouldUseBar(
        screen: ScreenInfo,
        visibleSectionMinX: CGFloat,
        hiddenItemsWidth: CGFloat
    ) -> Bool {
        guard let notch = notchRect(screen), hiddenItemsWidth > 0 else { return false }
        let revealedMinX = visibleSectionMinX - SectionLayout.dividerLength - hiddenItemsWidth
        return revealedMinX < notch.maxX
    }
}
