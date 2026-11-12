import AppKit
import Combine
import SwiftUI

/// The Awning module inside Hub: notch island, live activities, lock-screen card.
/// Created on the first `start()`. `stop()` parks it: the island leaves the screen, event monitors are
/// removed and no notices or lock card appear. The event-driven services stay loaded and idle.
public final class IslandModule {
    public static let shared = IslandModule()
    /// Set by Hub: opens Hub's Settings on the Island page.
    public var onOpenSettings: (() -> Void)?

    private var island: IslandController?
    private var lockScreen: LockScreenController?
    private var session: SessionWatcher?
    private let diagnostics = DiagnosticsSampler()
    private var cancellables = Set<AnyCancellable>()
    public private(set) var isRunning = false

    private init() {}

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        if let island {
            island.unpark()
            lockScreen?.parked = false
            return
        }
        let settings = AppSettings.shared
        let island = IslandController(settings: settings, onSettings: { [weak self] in self?.onOpenSettings?() })
        self.island = island
        lockScreen = LockScreenController(settings: settings, services: island.services)
        session = SessionWatcher { [weak self] change in
            guard let self, self.isRunning else { return }
            switch change {
            case .suspend: self.island?.suspend()
            case .resume: self.island?.resume()
            }
        }
        var lastMR = settings.useMediaRemote
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard settings.useMediaRemote != lastMR else { return }
                lastMR = settings.useMediaRemote
                self?.island?.services.player.setMediaRemote(lastMR)
            }
            .store(in: &cancellables)
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        island?.park()
        lockScreen?.parked = true
    }

    /// Hub closes the island before showing its Settings window.
    public func collapse() { island?.collapse() }

    /// One line for Hub's Overview.
    public var statusText: String {
        guard isRunning, let island else { return "Off" }
        let s = AppSettings.shared
        var parts: [String] = []
        if s.showNowPlaying {
            if let info = island.services.player.info {
                parts.append("♪ \(info.title)\(info.artist.isEmpty ? "" : " – \(info.artist)")")
            } else {
                parts.append("nothing playing")
            }
        }
        if s.showWeather { parts.append("weather: \(island.services.weather.status)") }
        parts.append(s.useMediaRemote ? (island.services.player.mediaRemoteActive ? "MediaRemote" : "MediaRemote failed, AppleScript") : "AppleScript")
        return parts.joined(separator: " · ")
    }

    /// The Island page of Hub's Settings. The CPU/memory sampler runs only while the page is shown.
    public func settingsPage() -> AnyView {
        guard let island else {
            return AnyView(Text("Turn the Island on to change its settings.").foregroundColor(.secondary).padding(40))
        }
        return AnyView(SettingsView(
            settings: AppSettings.shared, services: island.services,
            brightnessAvailable: island.brightnessAvailable,
            lockSupported: lockScreen?.isSupported ?? false,
            diagnostics: diagnostics)
            .onAppear { [diagnostics] in diagnostics.start() }
            .onDisappear { [diagnostics] in diagnostics.stop() })
    }

    /// Stops the diagnostics sampler (Hub calls this when its Settings window closes).
    public func settingsClosed() { diagnostics.stop() }
}
