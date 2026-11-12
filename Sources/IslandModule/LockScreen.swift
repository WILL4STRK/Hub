import AppKit
import SwiftUI

/// Private SkyLight calls used to place a window in a space above the lock screen.
/// Loaded with dlsym; if any symbol is missing the feature stays off.
/// Risk notes: undocumented, may change in any macOS update. A failure affects only Awning:
/// the space belongs to Awning's window-server connection and is removed when Awning quits.
final class SkyLight {
    typealias MainConnectionFn = @convention(c) () -> Int32
    typealias SpaceCreateFn = @convention(c) (Int32, Int32, Int32) -> UInt64
    typealias SpaceDestroyFn = @convention(c) (Int32, UInt64) -> Int32
    typealias SetLevelFn = @convention(c) (Int32, UInt64, Int32) -> Int32
    typealias ShowHideFn = @convention(c) (Int32, CFArray) -> Int32
    typealias AddWindowsFn = @convention(c) (Int32, UInt64, CFArray, Int32) -> Int32

    let mainConnection: MainConnectionFn
    let spaceCreate: SpaceCreateFn
    let spaceDestroy: SpaceDestroyFn
    let setLevel: SetLevelFn
    let showSpaces: ShowHideFn
    let hideSpaces: ShowHideFn
    let addWindows: AddWindowsFn

    init?() {
        guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let a = dlsym(h, "SLSMainConnectionID"),
              let b = dlsym(h, "SLSSpaceCreate"),
              let c = dlsym(h, "SLSSpaceDestroy"),
              let d = dlsym(h, "SLSSpaceSetAbsoluteLevel"),
              let e = dlsym(h, "SLSShowSpaces"),
              let f = dlsym(h, "SLSHideSpaces"),
              let g = dlsym(h, "SLSSpaceAddWindowsAndRemoveFromSpaces") else { return nil }
        mainConnection = unsafeBitCast(a, to: MainConnectionFn.self)
        spaceCreate = unsafeBitCast(b, to: SpaceCreateFn.self)
        spaceDestroy = unsafeBitCast(c, to: SpaceDestroyFn.self)
        setLevel = unsafeBitCast(d, to: SetLevelFn.self)
        showSpaces = unsafeBitCast(e, to: ShowHideFn.self)
        hideSpaces = unsafeBitCast(f, to: ShowHideFn.self)
        addWindows = unsafeBitCast(g, to: AddWindowsFn.self)
    }
}

/// Panel that can never take keyboard focus, so typing on the lock screen always reaches
/// the password field.
final class LockPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Shows a centered card (clock, now playing, widgets) while the screen is locked.
final class LockScreenController {
    private let settings: AppSettings
    private let services: Services
    /// Loaded on first use, so nothing is looked up while the lock-screen card is off.
    private lazy var skylight: SkyLight? = SkyLight()
    private var panel: LockPanel?
    private var connection: Int32 = 0
    private var space: UInt64 = 0
    private(set) var lastError: String?
    /// Island module switched off in Hub: never show the card.
    var parked = false

    static let cardSize = CGSize(width: 520, height: 208)

    var isSupported: Bool { skylight != nil }

    init(settings: AppSettings, services: Services) {
        self.settings = settings
        self.services = services
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(locked), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(unlocked), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        // Safety net: never leave the card up once the user session is active again.
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(unlocked),
                                                          name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    }

    @objc private func locked() {
        NSLog("Hub island lock: screenIsLocked received (enabled=%d)", settings.showOnLockScreen ? 1 : 0)
        guard settings.showOnLockScreen, !parked, let skylight else { return }
        let screen = ScreenLocator.target(id: settings.screenID) ?? NSScreen.main
        guard let screen else { return }

        let size = Self.cardSize
        // Horizontally centered. "bottom" sits below the profile picture and the
        // "Touch ID or Enter Password" hint; "top" sits under the menu-bar area. Both clear the login UI.
        let f = screen.frame
        let y = settings.lockCardPosition == "top"
            ? f.maxY - size.height - max(60, f.height * 0.08)
            : f.minY + min(max(settings.lockCardHeight, 0), f.height - size.height)
        let rect = NSRect(x: f.midX - size.width / 2, y: y, width: size.width, height: size.height)
        let p = panel ?? makePanel()
        p.setFrame(rect, display: true)
        p.orderFrontRegardless()

        if space == 0 {
            connection = skylight.mainConnection()
            space = skylight.spaceCreate(connection, 1, 0)
            guard space != 0 else { lastError = "SLSSpaceCreate returned 0"; return }
            // 400 orders the space above the lock screen's own layers.
            let level = skylight.setLevel(connection, space, 400)
            NSLog("Hub island lock: connection=%d space=%llu setLevel=%d", connection, space, level)
        }
        let shown = skylight.showSpaces(connection, [NSNumber(value: space)] as CFArray)
        let added = skylight.addWindows(connection, space, [NSNumber(value: p.windowNumber)] as CFArray, 7)
        NSLog("Hub island lock: window=%d frame=%@ showSpaces=%d addWindows=%d", p.windowNumber, NSStringFromRect(rect), shown, added)
        lastError = nil
    }

    @objc private func unlocked() {
        NSLog("Hub island lock: unlocked / session active")
        panel?.orderOut(nil)
        guard let skylight, space != 0 else { return }
        _ = skylight.hideSpaces(connection, [NSNumber(value: space)] as CFArray)
        _ = skylight.spaceDestroy(connection, space)
        space = 0
        // Recreate the window next time so it starts in a normal space.
        panel?.close()
        panel = nil
    }

    private func makePanel() -> LockPanel {
        let p = LockPanel(contentRect: NSRect(origin: .zero, size: Self.cardSize),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.animationBehavior = .none // removed in the same frame on unlock, no fade
        p.contentView = FirstMouseHostingView(rootView: LockCard(services: services))
        panel = p
        return p
    }
}

/// Two-row card: clock and widgets on top, now playing with the full song name below.
struct LockCard: View {
    let services: Services
    @ObservedObject private var player: NowPlayingService
    @ObservedObject private var weather: WeatherService
    @ObservedObject private var settings: AppSettings

    init(services: Services) {
        self.services = services
        _player = ObservedObject(wrappedValue: services.player)
        _weather = ObservedObject(wrappedValue: services.weather)
        _settings = ObservedObject(wrappedValue: services.settings)
    }

    var body: some View {
        VStack(spacing: 14) {
            // Row 1: clock and date, widgets on the right.
            HStack(alignment: .center) {
                TimelineView(.everyMinute) { context in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(context.date, format: .dateTime.hour().minute())
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        Text(context.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.65))
                    }
                }
                .foregroundColor(.white)
                Spacer()
                HStack(spacing: 8) {
                    if let b = PowerMonitor.current() {
                        widget(symbol: b.charging ? "battery.100.bolt" : "battery.75", text: "\(b.level)%")
                    }
                    if settings.showWeather, let w = weather.now {
                        widget(symbol: w.symbol, text: w.text)
                    }
                }
            }

            // Row 2: now playing with room for the full song name.
            if settings.showNowPlaying, let info = player.info {
                HStack(spacing: 12) {
                    ArtView(image: player.artLarge, size: 56, radius: 12)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(info.title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(info.artist)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    BubbleButton(symbol: "backward.fill", size: 30, action: player.previous)
                    BubbleButton(symbol: info.isPlaying ? "pause.fill" : "play.fill", size: 38, prominent: true,
                                 action: player.togglePlayPause)
                    BubbleButton(symbol: "forward.fill", size: 30, action: player.next)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.08)))
            } else {
                Text("Nothing playing")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: LockScreenController.cardSize.width, height: LockScreenController.cardSize.height)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1))
        )
    }

    private func widget(symbol: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).symbolRenderingMode(.multicolor)
            Text(text).monospacedDigit()
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule().fill(Color.white.opacity(0.12)))
    }
}
