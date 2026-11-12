// Notch support, kept small and isolated. This Mac has no notch, so this path
// is only exercised through the fake-screen checks in ShelfChecks.
import AppKit
import ShelfCore
import SwiftUI

extension NSScreen {
    var shelfInfo: ScreenInfo {
        ScreenInfo(frame: frame, safeAreaTop: safeAreaInsets.top,
                   auxiliaryTopLeft: auxiliaryTopLeftArea, auxiliaryTopRight: auxiliaryTopRightArea)
    }
}

/// Shows hidden items as buttons in a small bar below the menu bar.
final class ShelfBarPanel {
    private var panel: NSPanel?
    var isVisible: Bool { panel?.isVisible ?? false }

    func show(items: [MenuBarItem], screen: NSScreen, rightEdge: CGFloat, onPick: @escaping (MenuBarItem) -> Void) {
        close()
        let height: CGFloat = 34
        let width = CGFloat(items.count) * 30 + 12
        let menuBarBottom = screen.frame.maxY - NSStatusBar.system.thickness - max(screen.safeAreaInsets.top - NSStatusBar.system.thickness, 0)
        let x = min(rightEdge, screen.frame.maxX - 8) - width
        let frame = NSRect(x: max(x, screen.frame.minX + 8), y: menuBarBottom - height - 4, width: width, height: height)

        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        background.material = .menu
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        let host = NSHostingView(rootView: ShelfBarView(items: items, onPick: { [weak self] item in
            self?.close()
            onPick(item)
        }))
        host.frame = background.bounds
        host.autoresizingMask = [.width, .height]
        background.addSubview(host)
        panel.contentView = background
        panel.setAccessibilityLabel("Hidden menu bar items")
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct ShelfBarView: View {
    let items: [MenuBarItem]
    let onPick: (MenuBarItem) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items) { item in
                Button { onPick(item) } label: {
                    Image(nsImage: NSRunningApplication(processIdentifier: item.pid)?.icon ?? NSImage())
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .help(item.ownerName)
                .accessibilityLabel(item.ownerName)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
