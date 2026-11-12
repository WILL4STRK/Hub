import Foundation

/// User preferences, persisted in UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    /// Show a simulated island on screens that have no camera notch.
    @Published var simulateNotch: Bool {
        didSet { defaults.set(simulateNotch, forKey: "simulateNotch") }
    }

    /// "auto" or a CGDirectDisplayID as a string.
    @Published var screenID: String {
        didSet { defaults.set(screenID, forKey: "screenID") }
    }

    /// Show the current track in the island.
    @Published var showNowPlaying: Bool {
        didSet { defaults.set(showNowPlaying, forKey: "showNowPlaying") }
    }

    /// Animated audio bars in the collapsed pill while music plays.
    @Published var showAudioBars: Bool {
        didSet { defaults.set(showAudioBars, forKey: "showAudioBars") }
    }

    /// Soft glow in the album-art color around the pill while music plays.
    @Published var playingGlow: Bool { didSet { defaults.set(playingGlow, forKey: "playingGlow") } }

    /// Player started by the Play button when nothing is playing: "spotify" or "music".
    @Published var defaultPlayer: String {
        didSet { defaults.set(defaultPlayer, forKey: "defaultPlayer") }
    }

    // Live activities (Phase 3)
    @Published var showBatteryAlerts: Bool { didSet { defaults.set(showBatteryAlerts, forKey: "showBatteryAlerts") } }
    @Published var showBluetooth: Bool { didSet { defaults.set(showBluetooth, forKey: "showBluetooth") } }
    @Published var showVolumeHUD: Bool { didSet { defaults.set(showVolumeHUD, forKey: "showVolumeHUD") } }
    @Published var showBrightnessHUD: Bool { didSet { defaults.set(showBrightnessHUD, forKey: "showBrightnessHUD") } }
    @Published var showOutputPicker: Bool { didSet { defaults.set(showOutputPicker, forKey: "showOutputPicker") } }
    @Published var showWeather: Bool { didSet { defaults.set(showWeather, forKey: "showWeather") } }
    @Published var showLyrics: Bool { didSet { defaults.set(showLyrics, forKey: "showLyrics") } }

    // Notch size and position for the simulated island (Phase 4)
    /// Width in points of the simulated notch.
    @Published var notchWidth: Double { didSet { defaults.set(notchWidth, forKey: "notchWidth") } }
    /// Height in points; 0 matches the menu bar.
    @Published var notchHeight: Double { didSet { defaults.set(notchHeight, forKey: "notchHeight") } }
    /// Horizontal offset in points from the screen center (simulated notch only).
    @Published var notchOffset: Double { didSet { defaults.set(notchOffset, forKey: "notchOffset") } }

    /// First-launch tour shown inside the island.
    @Published var onboarded: Bool { didSet { defaults.set(onboarded, forKey: "onboarded") } }

    /// Private MediaRemote framework for now playing (all apps, browsers too). Off: AppleScript for Spotify and Music.
    @Published var useMediaRemote: Bool { didSet { defaults.set(useMediaRemote, forKey: "useMediaRemote") } }

    /// Centered card on the lock screen (private SkyLight API; off by default).
    @Published var showOnLockScreen: Bool { didSet { defaults.set(showOnLockScreen, forKey: "showOnLockScreen") } }
    /// Where the lock-screen card sits: "bottom" (below the login profile) or "top".
    @Published var lockCardPosition: String { didSet { defaults.set(lockCardPosition, forKey: "lockCardPosition") } }
    /// Distance in points from the bottom of the screen when the card is "below login".
    @Published var lockCardHeight: Double { didSet { defaults.set(lockCardHeight, forKey: "lockCardHeight") } }

    private init() {
        defaults.register(defaults: [
            "simulateNotch": true,
            "screenID": "auto",
            "showNowPlaying": true,
            "showAudioBars": true,
            "playingGlow": true,
            "defaultPlayer": "spotify",
            "showBatteryAlerts": true,
            "showBluetooth": true,
            "showVolumeHUD": true,
            "showBrightnessHUD": true,
            "showOutputPicker": true,
            "showWeather": true,
            "showLyrics": true,
            "notchWidth": 190.0,
            "notchHeight": 0.0,
            "notchOffset": 0.0,
            "onboarded": false,
            "useMediaRemote": true,
            "showOnLockScreen": false,
            "lockCardPosition": "bottom",
            "lockCardHeight": 185.0,
        ])
        simulateNotch = defaults.bool(forKey: "simulateNotch")
        screenID = defaults.string(forKey: "screenID") ?? "auto"
        showNowPlaying = defaults.bool(forKey: "showNowPlaying")
        showAudioBars = defaults.bool(forKey: "showAudioBars")
        playingGlow = defaults.bool(forKey: "playingGlow")
        defaultPlayer = defaults.string(forKey: "defaultPlayer") ?? "spotify"
        showBatteryAlerts = defaults.bool(forKey: "showBatteryAlerts")
        showBluetooth = defaults.bool(forKey: "showBluetooth")
        showVolumeHUD = defaults.bool(forKey: "showVolumeHUD")
        showBrightnessHUD = defaults.bool(forKey: "showBrightnessHUD")
        showOutputPicker = defaults.bool(forKey: "showOutputPicker")
        showWeather = defaults.bool(forKey: "showWeather")
        showLyrics = defaults.bool(forKey: "showLyrics")
        notchWidth = defaults.double(forKey: "notchWidth")
        notchHeight = defaults.double(forKey: "notchHeight")
        notchOffset = defaults.double(forKey: "notchOffset")
        onboarded = defaults.bool(forKey: "onboarded")
        useMediaRemote = defaults.bool(forKey: "useMediaRemote")
        showOnLockScreen = defaults.bool(forKey: "showOnLockScreen")
        lockCardPosition = defaults.string(forKey: "lockCardPosition") ?? "bottom"
        lockCardHeight = defaults.double(forKey: "lockCardHeight")
    }

    var defaultPlayerName: String { defaultPlayer == "music" ? "Music" : "Spotify" }
}

