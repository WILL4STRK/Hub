/// Hover reveal near the chevron, with a lockout after a manual click.
/// Without it, closing the sections by clicking the chevron reopened them at once, because the pointer
/// was still inside the hover zone. After a click, hover stays ignored until the pointer leaves the
/// zone; re-entering reveals again.
public struct HoverGate: Equatable {
    public private(set) var suppressed = false

    public init() {}

    /// Call on every chevron click (open or close).
    public mutating func manualClick() { suppressed = true }

    /// Call on every pointer move. Returns true when hover should reveal the hidden section now.
    public mutating func pointerMoved(inZone: Bool, isShowing: Bool) -> Bool {
        if !inZone {
            suppressed = false
            return false
        }
        return !suppressed && !isShowing
    }
}
