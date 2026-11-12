import AppKit
import SwiftUI

// MARK: Bubble building blocks (iOS-style)

/// Springy press feedback for bubble buttons.
struct BubblePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(Motion.feedback, value: configuration.isPressed)
    }
}

/// Round translucent button with an SF Symbol.
struct BubbleButton: View {
    let symbol: String
    var size: CGFloat = 34
    var prominent = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundColor(prominent ? .black : .white)
                .frame(width: size, height: size)
                .background(
                    Circle().fill(prominent
                        ? Color.white.opacity(hovering ? 1 : 0.92)
                        : Color.white.opacity(hovering ? 0.22 : 0.12))
                )
                .contentShape(Circle())
        }
        .buttonStyle(BubblePressStyle())
        .onHover { hovering = $0 }
    }
}

/// Capsule button with icon and label.
struct BubblePill: View {
    let symbol: String
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 12, weight: .bold))
                Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(Capsule().fill(Color.white.opacity(hovering ? 0.22 : 0.13)))
            .contentShape(Capsule())
        }
        .buttonStyle(BubblePressStyle())
        .onHover { hovering = $0 }
    }
}

/// Album art with continuous rounded corners, or a placeholder.
struct ArtView: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [Color(white: 0.28), Color(white: 0.16)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: Audio bars

/// Equalizer-style bars driven by Core Animation, so the render server animates them
/// and the app itself stays near 0% CPU.
final class AudioBarsView: NSView {
    private var bars: [CALayer] = []
    private static let durations: [CFTimeInterval] = [0.42, 0.56, 0.36, 0.5]

    var playing = false {
        didSet { if playing != oldValue { restart() } }
    }

    var color: NSColor = .white {
        didSet {
            guard color != oldValue else { return }
            for bar in bars { bar.backgroundColor = color.withAlphaComponent(0.95).cgColor }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for _ in Self.durations {
            let bar = CALayer()
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            layer?.addSublayer(bar)
            bars.append(bar)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(displayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    deinit { NSWorkspace.shared.notificationCenter.removeObserver(self) }

    @objc private func displayOptionsChanged() { restart() }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        let count = CGFloat(bars.count)
        let gap: CGFloat = 2
        let width = max(1, (bounds.width - gap * (count - 1)) / count)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height)
            bar.position = CGPoint(x: CGFloat(i) * (width + gap) + width / 2, y: 0)
            bar.cornerRadius = width / 2
        }
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        restart()
    }

    private func restart() {
        let now = CACurrentMediaTime()
        for (i, bar) in bars.enumerated() {
            bar.removeAllAnimations()
            bar.transform = CATransform3DMakeScale(1, 0.3, 1)
            // Reduce Motion: bars stay still at a fixed height.
            guard playing, window != nil, !Motion.reduced else { continue }
            let a = CABasicAnimation(keyPath: "transform.scale.y")
            a.fromValue = 0.3
            a.toValue = 1.0
            a.duration = Self.durations[i]
            a.autoreverses = true
            a.repeatCount = .infinity
            a.beginTime = now + Double(i) * 0.08
            a.fillMode = .backwards
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.add(a, forKey: "bounce")
        }
    }
}

struct AudioBars: NSViewRepresentable {
    var playing: Bool
    var color: NSColor? = nil

    func makeNSView(context: Context) -> AudioBarsView {
        let v = AudioBarsView(frame: .zero)
        v.playing = playing
        v.color = color ?? .white
        return v
    }

    func updateNSView(_ nsView: AudioBarsView, context: Context) {
        nsView.playing = playing
        nsView.color = color ?? .white
    }
}

// MARK: Collapsed wings

/// Small art on the left of the notch and audio bars on the right.
struct CollapsedWings: View {
    @ObservedObject var player: NowPlayingService
    @ObservedObject var settings: AppSettings
    let notchWidth: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ArtView(image: player.artSmall, size: NowPlayingService.smallArtPoints, radius: 5)
                .frame(width: IslandModel.wingWidth)
            Spacer().frame(width: notchWidth)
            Group {
                if settings.showAudioBars {
                    AudioBars(playing: player.info?.isPlaying ?? false, color: player.accent)
                        .frame(width: 15, height: min(12, height - 10))
                }
            }
            .frame(width: IslandModel.wingWidth)
        }
        .frame(height: height)
    }
}

// MARK: Expanded card

struct NowPlayingCard: View {
    @ObservedObject var player: NowPlayingService
    @ObservedObject var settings: AppSettings
    @ObservedObject var lyrics: LyricsService

    var body: some View {
        if !settings.showNowPlaying {
            emptyState(message: "Now playing is turned off in Settings")
        } else if let info = player.info {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    ArtView(image: player.artLarge, size: NowPlayingService.largeArtPoints, radius: 14)
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(info.title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(info.artist.isEmpty ? (info.appName ?? "") : info.artist)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                        if settings.showLyrics && !lyrics.lines.isEmpty {
                            LyricLineView(info: info, lyrics: lyrics)
                        }
                    }
                    Spacer(minLength: 8)
                    AudioBars(playing: info.isPlaying, color: player.accent)
                        .frame(width: 18, height: 16)
                }

                ScrubBar(info: info, onSeek: { player.seek(to: $0) })

                HStack(spacing: 22) {
                    BubbleButton(symbol: "backward.fill", action: player.previous)
                    BubbleButton(symbol: info.isPlaying ? "pause.fill" : "play.fill", size: 42, prominent: true,
                                 action: player.togglePlayPause)
                    BubbleButton(symbol: "forward.fill", action: player.next)
                }
            }
        } else {
            emptyState(message: "Nothing playing", showPlay: true)
        }
    }

    private func emptyState(message: String, showPlay: Bool = false) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
            if showPlay {
                BubblePill(symbol: "play.fill", title: "Play \(settings.defaultPlayerName)", action: player.playDefault)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Progress capsule that can be dragged to seek. Ticks once a second only while playing.
struct ScrubBar: View {
    let info: NowPlayingInfo
    let onSeek: (Double) -> Void
    @State private var dragFraction: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: info.isPlaying ? 1 : 3600)) { context in
            let position = dragFraction.map { $0 * info.duration } ?? info.position(at: context.date)
            let fraction = info.duration > 0 ? min(max(position / info.duration, 0), 1) : 0
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.16))
                        Capsule().fill(Color.white.opacity(0.92))
                            .frame(width: max(0, geo.size.width * fraction))
                    }
                    .frame(height: dragFraction == nil ? 5 : 8)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(info.duration > 0 ? DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            dragFraction = min(max(v.location.x / geo.size.width, 0), 1)
                        }
                        .onEnded { v in
                            let f = min(max(v.location.x / geo.size.width, 0), 1)
                            onSeek(f * info.duration)
                            dragFraction = nil
                        } : nil)
                    .animation(Motion.feedback, value: dragFraction == nil)
                }
                .frame(height: 12)

                HStack {
                    Text(Self.format(position))
                    Spacer()
                    Text("-" + Self.format(max(0, info.duration - position)))
                }
                .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let s = Int(seconds.rounded(.down))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// The synced lyric line for the current position; ticks only while playing.
struct LyricLineView: View {
    let info: NowPlayingInfo
    @ObservedObject var lyrics: LyricsService

    var body: some View {
        TimelineView(.periodic(from: .now, by: info.isPlaying ? 0.5 : 3600)) { context in
            Text(lyrics.line(at: info.position(at: context.date)) ?? "♪")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.88))
                .lineLimit(1)
                .id(lyrics.line(at: info.position(at: context.date)) ?? "")
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(Motion.feedback, value: lyrics.line(at: info.position(at: context.date)))
        }
    }
}
