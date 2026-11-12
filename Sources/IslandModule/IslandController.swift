import AppKit
import Combine
import SwiftUI

/// Borderless, non-activating panel that sits above the menu bar.
final class IslandPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        // No .fullScreenAuxiliary: the island stays out of full-screen Spaces.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that reacts to the first click even though the app is never active.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the island panel: placement, hover, open/close and event monitors.
final class IslandController {
    static let panelSize = CGSize(width: 640, height: 340)

    let model = IslandModel()
    let services: Services
    private var player: NowPlayingService { services.player }
    private let settings: AppSettings
    private var power: PowerMonitor?
    private var bluetooth: BluetoothMonitor?
    private var brightness: BrightnessMonitor?
    private var toastWork: DispatchWorkItem?
    private let panel: IslandPanel
    private var monitors: [Any] = []
    private var cancellables = Set<AnyCancellable>()
    /// True while the screen is locked or asleep, or another user is active.
    private(set) var isSuspended = false

    init(settings: AppSettings, onSettings: @escaping () -> Void) {
        self.settings = settings
        services = Services(settings: settings)
        panel = IslandPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize))

        panel.contentView = FirstMouseHostingView(rootView: IslandRootView(
            model: model,
            services: services,
            onTap: { [weak self] in self?.expand() },
            onSettings: onSettings,
            onFinishOnboarding: { [weak self] in self?.finishOnboarding() }))
        panel.ignoresMouseEvents = true

        installMonitors()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.reposition() }

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.reposition()
                self?.updateWings()
                self?.startOnboardingIfNeeded()
            }
            .store(in: &cancellables)

        player.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                self.updateWings()
                self.services.lyrics.update(for: self.player.info)
            }
            .store(in: &cancellables)

        startLiveActivities()
        startOnboardingIfNeeded()

        reposition()
    }

    // MARK: Placement

    func reposition() {
        // Nothing is ordered in while locked or asleep; resume() places the panel again.
        guard !isSuspended else { return }
        guard let screen = ScreenLocator.target(id: settings.screenID) else {
            panel.orderOut(nil)
            return
        }
        let real = ScreenLocator.notchSize(of: screen)
        if real == nil && !settings.simulateNotch {
            panel.orderOut(nil)
            return
        }
        model.hasRealNotch = real != nil
        model.notchSize = real ?? ScreenLocator.simulatedSize(of: screen, width: settings.notchWidth,
                                                              height: settings.notchHeight)

        let f = screen.frame
        let size = Self.panelSize
        // Offset applies only to a simulated notch; a real one is fixed in hardware.
        let maxOffset = f.width / 2 - size.width / 2
        let offset = real == nil ? min(max(settings.notchOffset, -maxOffset), maxOffset) : 0
        panel.setFrame(NSRect(x: (f.midX - size.width / 2 + offset).rounded(),
                              y: f.maxY - size.height,
                              width: size.width, height: size.height),
                       display: true)
        panel.orderFrontRegardless()
    }

    // MARK: Live activities

    private func startLiveActivities() {
        power = PowerMonitor { [weak self] toast in
            guard let self, self.settings.showBatteryAlerts else { return }
            self.show(toast)
        }
        bluetooth = BluetoothMonitor { [weak self] toast in
            guard let self, self.settings.showBluetooth else { return }
            self.show(toast)
        }
        services.audio.onVolume = { [weak self] volume, muted in
            guard let self, self.settings.showVolumeHUD else { return }
            self.show(.level(kind: .volume, value: Double(volume), muted: muted))
        }
        services.audio.onOutputChanged = { [weak self] name in
            guard let self, self.settings.showOutputPicker else { return }
            self.show(.output(name: name))
        }
        brightness = BrightnessMonitor(isEnabled: { [weak self] in self?.settings.showBrightnessHUD ?? false }) { [weak self] value in
            self?.show(.level(kind: .brightness, value: value, muted: false))
        }
        services.weather.refreshIfStale()
    }

    /// Shows a transient notice; skipped while the full card is open.
    func show(_ toast: Toast) {
        guard !isSuspended, model.state != .expanded, panel.isVisible else { return }
        toastWork?.cancel()
        Motion.perform(showing: true) { model.toast = toast }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Dismissal is instant: no fade-out, the pill is back in the same frame.
            Motion.perform(showing: false) { self.model.toast = nil }
            self.updateMouse()
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + toast.lifetime, execute: work)
        updateMouse()
    }

    var brightnessAvailable: Bool { brightness?.isAvailable ?? false }

    // MARK: State

    // MARK: Onboarding

    func startOnboardingIfNeeded() {
        guard !settings.onboarded, !model.onboarding else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, !self.isSuspended, !self.settings.onboarded, self.panel.isVisible else { return }
            self.model.onboarding = true
            self.expand()
        }
    }

    private func finishOnboarding() {
        settings.onboarded = true
        collapse()
        // Collapse is instant, so the tour can be cleared in the same frame.
        model.onboarding = false
    }

    /// Widens the collapsed pill while a track is loaded.
    private func updateWings() {
        let show = settings.showNowPlaying && player.info != nil
        guard show != model.wings else { return }
        if isSuspended {
            model.wings = show // drawn on resume; no animation while hidden
            return
        }
        Motion.perform(showing: show) { model.wings = show }
        updateMouse()
    }

    func expand() { setState(.expanded) }

    func collapse() {
        if model.state != .collapsed { setState(.collapsed) }
    }

    private func setState(_ state: IslandState) {
        guard model.state != state else { return }
        // Growing animates for 0.18 s; shrinking (closing the card or the hover peek) is instant,
        // so its glass, shadow and content are gone in the same frame.
        let seconds = MotionPolicy.duration(from: model.state, to: state, reduceMotion: Motion.reduced)
        Motion.perform(seconds) {
            model.state = state
            if state == .expanded { model.toast = nil }
        }
        if state == .expanded {
            panel.ignoresMouseEvents = false
            panel.makeKey()
        } else if panel.isKeyWindow {
            panel.resignKey()
        }
        updateMouse()
    }

    /// Screen-space rectangle the island currently occupies (slightly padded when small).
    private func hitRect() -> NSRect {
        var size = model.currentSize
        if model.state != .expanded {
            size.width += 12
            size.height += 6
        }
        let f = panel.frame
        // Extend 2 pt above the top edge so the pointer pinned at the screen edge still counts.
        return NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height,
                      width: size.width, height: size.height + 2)
    }

    // MARK: Lock, sleep and user switching

    /// Closes the card, toast and hover peek at once and takes the island off screen.
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        toastWork?.cancel()
        toastWork = nil
        Motion.perform(0) {
            model.state = .collapsed
            model.toast = nil
        }
        if panel.isKeyWindow { panel.resignKey() }
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
    }

    /// Island switched off in Hub: off screen, no event monitors, no notices. Services stay loaded but idle.
    private(set) var parked = false

    func park() {
        guard !parked else { return }
        suspend()
        parked = true
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
    }

    func unpark() {
        guard parked else { return }
        parked = false
        installMonitors()
        resume()
        startOnboardingIfNeeded()
    }

    /// Shows the plain pill again (no stale toast or card) and refreshes now playing.
    func resume() {
        guard isSuspended, !parked else { return }
        isSuspended = false
        player.refresh()
        let wings = settings.showNowPlaying && player.info != nil
        Motion.perform(0) { model.wings = wings }
        reposition()
        updateMouse()
    }

    private func updateMouse() {
        guard !isSuspended else { return }
        let inside = hitRect().contains(NSEvent.mouseLocation)
        // Only touch the window server when the value actually changes; this runs on every mouse move.
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        switch model.state {
        case .collapsed where inside: setState(.hovered)
        case .hovered where !inside: setState(.collapsed)
        default: break
        }
    }

    // MARK: Events

    private func installMonitors() {
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            self?.updateMouse()
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            self?.updateMouse()
            return event
        }) { monitors.append(m) }

        // A click in another app closes the card.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.collapse()
        }) { monitors.append(m) }

        // A click in one of our other windows (Settings) closes it too.
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            if let self, event.window !== self.panel { self.collapse() }
            return event
        }) { monitors.append(m) }

        // Esc closes the card (the panel is key while expanded).
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, event.keyCode == 53, self.model.state == .expanded else { return event }
            self.collapse()
            return nil
        }) { monitors.append(m) }
    }
}
