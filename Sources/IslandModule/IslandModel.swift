import Foundation

/// View state shared by the controller and the SwiftUI island.
final class IslandModel: ObservableObject {
    @Published var state: IslandState = .collapsed
    @Published var notchSize = CGSize(width: 190, height: 32)
    @Published var hasRealNotch = false
    /// Art and audio bars beside the notch while something is playing.
    @Published var wings = false
    /// Transient notice (battery, Bluetooth, volume…) shown instead of the plain pill.
    @Published var toast: Toast?
    /// First-launch tour is showing inside the expanded card.
    @Published var onboarding = false

    static let wingWidth: CGFloat = 34

    /// Outward-curving shoulders where the island meets the top of the screen.
    private var showingToast: Bool { toast != nil && state != .expanded }

    var shoulder: CGFloat {
        if showingToast { return 8 }
        switch state {
        case .collapsed: return 4
        case .hovered: return 6
        case .expanded: return 10
        }
    }

    var bottomRadius: CGFloat {
        if showingToast { return 20 }
        switch state {
        case .collapsed: return min(notchSize.height / 2, 11)
        case .hovered: return 14
        case .expanded: return 30
        }
    }

    private var wingsWidth: CGFloat { wings ? 2 * Self.wingWidth : 0 }

    /// Full size of the drawn shape, shoulders included.
    var currentSize: CGSize {
        if showingToast {
            return CGSize(width: max(340, notchSize.width + 170), height: notchSize.height + 46)
        }
        switch state {
        case .collapsed:
            return CGSize(width: notchSize.width + 2 * shoulder + wingsWidth, height: notchSize.height)
        case .hovered:
            return CGSize(width: notchSize.width + 18 + 2 * shoulder + wingsWidth, height: notchSize.height + 6)
        case .expanded:
            return CGSize(width: max(420, notchSize.width + 140), height: 214)
        }
    }
}
