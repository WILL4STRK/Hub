import AppKit
import SwiftUI

/// A borderless, see-through window that lives on the desktop layer: above the wallpaper and desktop icons,
/// below every app window, on every Space, and out of Cmd-Tab and Mission Control. Like a real widget.
final class DesktopPanel: NSPanel {
    let key: String

    init<Content: View>(key: String, size: CGSize, defaultOrigin: CGPoint, @ViewBuilder content: (PanelHandle) -> Content) {
        self.key = key
        super.init(contentRect: CGRect(origin: defaultOrigin, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false  // the card draws its own soft shadow
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true  // only the prompt's text field takes the keyboard
        animationBehavior = .none

        let handle = PanelHandle()
        let host = NSHostingView(rootView: content(handle))
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: size)
        contentView = host
        handle.panel = self

        let name = "ClaudeWidgets.\(key)"
        if !setFrameUsingName(name) { setFrameOrigin(defaultOrigin) }
        setContentSize(size)
        setFrameAutosaveName(name)
        keepOnScreen()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// After a display change, pull the widget back if it ended up off every screen.
    func keepOnScreen() {
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(frame.insetBy(dx: 40, dy: 40)) }
        if !visible, let main = NSScreen.main {
            setFrameOrigin(CGPoint(x: main.visibleFrame.maxX - frame.width - 20, y: main.visibleFrame.maxY - frame.height - 20))
        }
    }
}

/// Lets a SwiftUI view reach its panel: to start a drag, or give the keyboard back.
@MainActor
final class PanelHandle: ObservableObject {
    weak var panel: DesktopPanel?
    /// Double-click pops the lock bar up; a locked widget cannot be dragged. The lock is remembered.
    @Published var showBar = false
    @Published var locked = UserDefaults.standard.bool(forKey: "ClaudeWidgets.locked") {
        didSet { UserDefaults.standard.set(locked, forKey: "ClaudeWidgets.locked") }
    }
    private var barTimer: Timer?
    private var defaultsObserver: Any?

    init() {
        // Hub's Widgets settings page writes the same key; follow it.
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            let v = UserDefaults.standard.bool(forKey: "ClaudeWidgets.locked")
            let me = self
            Task { @MainActor in if me?.locked != v { me?.locked = v } }
        }
    }

    func toggleBar() {
        showBar.toggle()
        barTimer?.invalidate()
        if showBar { barTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in let me = self; Task { @MainActor in me?.showBar = false } } }
    }

    func toggleLock() {
        locked.toggle()
        toggleBar(); toggleBar()  // restart the 5 s hide timer
    }

    /// Moves the widget with the mouse (call from a drag gesture). Runs until the mouse is released.
    func beginDrag() {
        guard let panel, let event = NSApp.currentEvent, event.type == .leftMouseDragged || event.type == .leftMouseDown else { return }
        panel.performDrag(with: event)
    }

    func focus() {
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKey()
    }

    func resignFocus() {
        panel?.makeFirstResponder(nil)
    }
}

/// Drag anywhere on a card (except controls) to move the widget.
struct DragToMove: ViewModifier {
    @ObservedObject var handle: PanelHandle
    @StateObject private var flag = DragFlag()
    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { _ in
                    guard !flag.on, !handle.locked else { return }
                    flag.on = true
                    handle.beginDrag()
                    flag.on = false
                }
        )
    }
}

extension View {
    func dragToMove(_ handle: PanelHandle) -> some View { modifier(DragToMove(handle: handle)) }
}

/// The bar a double-click pops up along the bottom of the widget.
struct LockBar: ViewModifier {
    @ObservedObject var handle: PanelHandle
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if handle.showBar {
                    HStack(spacing: 8) {
                        Image(systemName: handle.locked ? "lock.fill" : "lock.open").foregroundColor(handle.locked ? .green : .secondary)
                        Text(handle.locked ? "Position locked" : "Drag to move").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button(handle.locked ? "Unlock" : "Lock in place") { handle.toggleLock() }
                            .buttonStyle(.borderedProminent).controlSize(.small).tint(.green)
                    }
                    .padding(.horizontal, 14).frame(height: 38).frame(maxWidth: .infinity)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .padding(Theme.inset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: handle.showBar)
            .onTapGesture(count: 2) { handle.toggleBar() }
    }
}

extension View {
    func lockBar(_ handle: PanelHandle) -> some View { modifier(LockBar(handle: handle)) }
}

final class DragFlag: ObservableObject {
    var on = false
}
