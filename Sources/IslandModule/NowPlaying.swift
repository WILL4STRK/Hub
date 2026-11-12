import AppKit
import ImageIO

struct NowPlayingInfo: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    /// Elapsed seconds measured at `timestamp`.
    var elapsed: Double
    var timestamp: Date
    var isPlaying: Bool
    var appName: String?

    /// Current position, extrapolated from the last report while playing.
    func position(at date: Date) -> Double {
        guard isPlaying else { return elapsed }
        let p = elapsed + date.timeIntervalSince(timestamp)
        return duration > 0 ? min(max(p, 0), duration) : max(p, 0)
    }
}

/// MediaRemote private framework, loaded with dlopen (works on macOS 13).
final class MediaRemote {
    typealias InfoBlock = @convention(block) (CFDictionary?) -> Void
    typealias BoolBlock = @convention(block) (Bool) -> Void
    typealias PIDBlock = @convention(block) (Int32) -> Void
    typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping InfoBlock) -> Void
    typealias GetBoolFn = @convention(c) (DispatchQueue, @escaping BoolBlock) -> Void
    typealias GetPIDFn = @convention(c) (DispatchQueue, @escaping PIDBlock) -> Void
    typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
    typealias SendFn = @convention(c) (UInt32, CFDictionary?) -> Bool
    typealias SetElapsedFn = @convention(c) (Double) -> Void

    enum Command: UInt32 {
        case togglePlayPause = 2
        case next = 4
        case previous = 5
    }

    static let notifications = [
        "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
    ]

    let getInfo: GetInfoFn
    let getIsPlaying: GetBoolFn
    let getPID: GetPIDFn
    let register: RegisterFn
    let send: SendFn
    let setElapsed: SetElapsedFn

    init?() {
        guard let h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW),
              let a = dlsym(h, "MRMediaRemoteGetNowPlayingInfo"),
              let b = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying"),
              let c = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationPID"),
              let d = dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications"),
              let e = dlsym(h, "MRMediaRemoteSendCommand"),
              let f = dlsym(h, "MRMediaRemoteSetElapsedTime") else { return nil }
        getInfo = unsafeBitCast(a, to: GetInfoFn.self)
        getIsPlaying = unsafeBitCast(b, to: GetBoolFn.self)
        getPID = unsafeBitCast(c, to: GetPIDFn.self)
        register = unsafeBitCast(d, to: RegisterFn.self)
        send = unsafeBitCast(e, to: SendFn.self)
        setElapsed = unsafeBitCast(f, to: SetElapsedFn.self)
    }
}

/// Tracks what is playing: MediaRemote first (covers browsers too), AppleScript for
/// Spotify and Music when MediaRemote reports nothing. Event driven, no polling.
final class NowPlayingService: ObservableObject {
    enum Source { case none, mediaRemote, spotify, music }

    @Published private(set) var info: NowPlayingInfo?
    @Published private(set) var artLarge: NSImage?
    @Published private(set) var artSmall: NSImage?
    /// Vivid color taken from the album art; nil without art.
    @Published private(set) var accent: NSColor?

    static let largeArtPoints: CGFloat = 60
    static let smallArtPoints: CGFloat = 18

    private let settings: AppSettings
    /// nil when the MediaRemote switch is off or the framework failed to load: AppleScript for Spotify and Music.
    private var mr: MediaRemote?
    /// True when MediaRemote is switched on and loaded.
    var mediaRemoteActive: Bool { mr != nil }
    private let scriptQueue = DispatchQueue(label: "awning.applescript")
    private var source: Source = .none
    private var artKey: Int?
    private var pending: DispatchWorkItem?

    init(settings: AppSettings) {
        self.settings = settings
        if settings.useMediaRemote { mr = MediaRemote() }
        mr?.register(.main)
        for name in MediaRemote.notifications {
            NotificationCenter.default.addObserver(self, selector: #selector(changed),
                                                   name: NSNotification.Name(name), object: nil)
        }
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(changed),
                        name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"), object: nil)
        dnc.addObserver(self, selector: #selector(changed),
                        name: NSNotification.Name("com.apple.Music.playerInfo"), object: nil)
        refresh()
    }

    /// Follows the MediaRemote switch. Off (or failing to load): AppleScript for Spotify and Music.
    func setMediaRemote(_ on: Bool) {
        guard on != (mr != nil) else { return }
        if on {
            mr = MediaRemote()
            mr?.register(.main)
            if mr == nil { NSLog("Hub island: MediaRemote failed to load; using AppleScript for Spotify and Music") }
        } else {
            mr = nil
        }
        source = .none
        refresh()
    }

    /// Coalesces bursts of change notifications.
    @objc private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func refresh() {
        guard let mr else { refreshFromScripts(); return }
        mr.getInfo(.main) { [weak self] dict in
            guard let self else { return }
            let d = (dict as NSDictionary?) as? [String: Any] ?? [:]
            let title = d["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
            guard !title.isEmpty else { self.refreshFromScripts(); return }
            mr.getIsPlaying(.main) { playing in
                mr.getPID(.main) { pid in
                    let app = NSRunningApplication(processIdentifier: pid)?.localizedName
                    let info = NowPlayingInfo(
                        title: title,
                        artist: d["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "",
                        album: d["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? "",
                        duration: (d["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue ?? 0,
                        elapsed: (d["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue ?? 0,
                        timestamp: d["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date ?? Date(),
                        isPlaying: playing,
                        appName: app)
                    self.apply(info, artData: d["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data, source: .mediaRemote)
                }
            }
        }
    }

    // MARK: AppleScript fallback

    private func refreshFromScripts() {
        let spotifyRunning = Self.isRunning("com.spotify.client")
        let musicRunning = Self.isRunning("com.apple.Music")
        guard spotifyRunning || musicRunning else { clear(); return }
        scriptQueue.async { [weak self] in
            let spotify = spotifyRunning ? Self.parse(Self.run(Self.spotifyQuery)?.stringValue, msDuration: true, app: "Spotify") : nil
            let music = musicRunning ? Self.parse(Self.run(Self.musicQuery)?.stringValue, msDuration: false, app: "Music") : nil
            // Prefer whichever is playing; Music art comes through AppleScript, Spotify's needs the network, so skip it.
            var pick: (NowPlayingInfo, Source)?
            if let s = spotify, s.isPlaying { pick = (s, .spotify) }
            else if let m = music, m.isPlaying { pick = (m, .music) }
            else if let s = spotify { pick = (s, .spotify) }
            else if let m = music { pick = (m, .music) }
            var art: Data?
            if let p = pick, p.1 == .music { art = Self.run(Self.musicArt)?.data }
            DispatchQueue.main.async {
                guard let self else { return }
                if let p = pick { self.apply(p.0, artData: art, source: p.1) } else { self.clear() }
            }
        }
    }

    private static let spotifyQuery = """
    tell application "Spotify"
        if player state is stopped then return ""
        set t to current track
        return (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & (duration of t) & linefeed & (player position) & linefeed & (player state as string)
    end tell
    """

    private static let musicQuery = """
    tell application "Music"
        if player state is stopped then return ""
        set t to current track
        return (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & (duration of t) & linefeed & (player position) & linefeed & (player state as string)
    end tell
    """

    private static let musicArt = """
    tell application "Music"
        try
            return data of artwork 1 of current track
        on error
            return ""
        end try
    end tell
    """

    private static func parse(_ text: String?, msDuration: Bool, app: String) -> NowPlayingInfo? {
        guard let text, !text.isEmpty else { return nil }
        let parts = text.components(separatedBy: "\n")
        guard parts.count >= 6 else { return nil }
        func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        let duration = num(parts[3]) / (msDuration ? 1000 : 1)
        return NowPlayingInfo(title: parts[0], artist: parts[1], album: parts[2],
                              duration: duration, elapsed: num(parts[4]), timestamp: Date(),
                              isPlaying: parts[5] == "playing", appName: app)
    }

    @discardableResult
    private static func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("Awning AppleScript error: %@", error) }
        return result
    }

    private static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    // MARK: State

    private func apply(_ new: NowPlayingInfo, artData: Data?, source: Source) {
        let trackChanged = info?.title != new.title || info?.artist != new.artist
        self.source = source
        if info != new { info = new }
        if let artData, !artData.isEmpty {
            let key = artData.hashValue
            if key != artKey {
                artKey = key
                artLarge = Self.downsample(artData, points: Self.largeArtPoints)
                artSmall = Self.downsample(artData, points: Self.smallArtPoints)
                accent = artSmall.flatMap(Self.accentColor(of:))
            }
        } else if trackChanged {
            artKey = nil
            artLarge = nil
            artSmall = nil
            accent = nil
        }
    }

    private func clear() {
        source = .none
        if info != nil { info = nil }
        artKey = nil
        artLarge = nil
        artSmall = nil
        accent = nil
    }

    /// Average color of the art, pushed bright and saturated enough to read on black.
    static func accentColor(of image: NSImage) -> NSColor? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let base = NSColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                           blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        if s < 0.12 { return NSColor(white: 0.92, alpha: 1) } // grey art: stay neutral
        return NSColor(hue: h, saturation: min(1, max(s * 1.25, 0.45)), brightness: max(b, 0.85), alpha: 1)
    }

    /// Decodes artwork straight to the pixel size it is drawn at.
    static func downsample(_ data: Data, points: CGFloat) -> NSImage? {
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let thumb = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: points * scale,
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumb) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: points, height: points))
    }

    // MARK: Controls

    private var appName: String? {
        switch source {
        case .spotify: return "Spotify"
        case .music: return "Music"
        default: return nil
        }
    }

    func togglePlayPause() {
        switch source {
        case .mediaRemote: _ = mr?.send(MediaRemote.Command.togglePlayPause.rawValue, nil)
        case .spotify, .music: script("playpause")
        case .none: playDefault(); return
        }
        // Optimistic update; the next notification corrects it.
        if var i = info {
            let now = Date()
            i.elapsed = i.position(at: now)
            i.timestamp = now
            i.isPlaying.toggle()
            info = i
        }
    }

    func next() {
        if source == .mediaRemote { _ = mr?.send(MediaRemote.Command.next.rawValue, nil) } else { script("next track") }
    }

    func previous() {
        if source == .mediaRemote { _ = mr?.send(MediaRemote.Command.previous.rawValue, nil) } else { script("previous track") }
    }

    func seek(to seconds: Double) {
        if source == .mediaRemote { mr?.setElapsed(seconds) } else { script("set player position to \(seconds)") }
        if var i = info {
            i.elapsed = seconds
            i.timestamp = Date()
            info = i
        }
    }

    /// Starts the preferred player (launching it if needed).
    func playDefault() {
        let app = settings.defaultPlayerName
        scriptQueue.async { Self.run("tell application \"\(app)\" to play") }
    }

    private func script(_ command: String) {
        guard let app = appName else { return }
        scriptQueue.async { Self.run("tell application \"\(app)\" to \(command)") }
    }
}
