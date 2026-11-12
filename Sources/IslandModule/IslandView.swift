import AppKit
import SwiftUI

/// Island outline: a flat top edge with small outward shoulders that blend into the
/// screen edge, straight sides and soft bottom corners.
struct IslandShape: Shape {
    var shoulder: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(shoulder, bottomRadius) }
        set { shoulder = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let s = min(shoulder, w / 4)
        let r = min(bottomRadius, (w - 2 * s) / 2, h - s)
        // Control-point factor for a smoother, continuous-looking corner than a circular arc.
        let k: CGFloat = 0.45

        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: s, y: s), control: CGPoint(x: s, y: 0))
        p.addLine(to: CGPoint(x: s, y: h - r))
        p.addCurve(to: CGPoint(x: s + r, y: h),
                   control1: CGPoint(x: s, y: h - r * k),
                   control2: CGPoint(x: s + r * k, y: h))
        p.addLine(to: CGPoint(x: w - s - r, y: h))
        p.addCurve(to: CGPoint(x: w - s, y: h - r),
                   control1: CGPoint(x: w - s - r * k, y: h),
                   control2: CGPoint(x: w - s, y: h - r * k))
        p.addLine(to: CGPoint(x: w - s, y: s))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - s, y: 0))
        p.closeSubpath()
        return p
    }
}

/// Behind-window blur from AppKit.
struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Everything the island views read from.
final class Services {
    let settings: AppSettings
    let player: NowPlayingService
    let weather: WeatherService
    let lyrics: LyricsService
    let audio: AudioOutputs

    init(settings: AppSettings) {
        self.settings = settings
        player = NowPlayingService(settings: settings)
        weather = WeatherService(settings: settings)
        lyrics = LyricsService(settings: settings)
        audio = AudioOutputs()
    }
}

struct IslandRootView: View {
    @ObservedObject var model: IslandModel
    let services: Services
    var onTap: () -> Void
    var onSettings: () -> Void
    var onFinishOnboarding: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            IslandBody(model: model, services: services, onTap: onTap, onSettings: onSettings,
                       onFinishOnboarding: onFinishOnboarding)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct IslandBody: View {
    @ObservedObject var model: IslandModel
    let services: Services
    var onTap: () -> Void
    var onSettings: () -> Void
    var onFinishOnboarding: () -> Void

    var body: some View {
        let expanded = model.state == .expanded
        let toast = expanded ? nil : model.toast
        let shape = IslandShape(shoulder: model.shoulder, bottomRadius: model.bottomRadius)
        let size = model.currentSize

        ZStack(alignment: .top) {
            // Glow in the album-art color while music plays (static: no per-frame cost).
            PlayingGlow(player: services.player, settings: services.settings, shape: shape,
                        visible: model.wings && !expanded && toast == nil)

            // Glass: blur, a dark tint and a faint top highlight. Fades in when expanded.
            VisualEffectBlur()
                .clipShape(shape)
                .opacity(expanded ? 1 : 0)
            shape
                .fill(LinearGradient(colors: [Color.black.opacity(0.62), Color.black.opacity(0.78)],
                                     startPoint: .top, endPoint: .bottom))
                .opacity(expanded ? 1 : 0)
            shape
                .fill(LinearGradient(stops: [
                    .init(color: .white.opacity(0.0), location: 0.0),
                    .init(color: .white.opacity(0.07), location: 0.18),
                    .init(color: .white.opacity(0.0), location: 0.45),
                ], startPoint: .top, endPoint: .bottom))
                .opacity(expanded ? 1 : 0)

            // Solid black pill while collapsed, hovered or showing a toast.
            shape
                .fill(Color.black)
                .opacity(expanded ? 0 : 1)

            if let toast {
                ToastView(toast: toast)
                    .padding(.top, model.notchSize.height)
                    .padding(.horizontal, model.shoulder + 16)
                    .frame(height: size.height)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                    .id(toast.identity)
            } else if model.wings && !expanded {
                CollapsedWings(player: services.player, settings: services.settings,
                               notchWidth: size.width - 2 * model.shoulder - 2 * IslandModel.wingWidth,
                               height: size.height)
                    .transition(.opacity)
            }

            if expanded && model.onboarding {
                OnboardingView(topInset: model.notchSize.height, onSettings: onSettings, onDone: onFinishOnboarding)
                    .padding(.horizontal, model.shoulder + 22)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else if expanded {
                ExpandedContent(topInset: model.notchSize.height, services: services, onSettings: onSettings)
                    .padding(.horizontal, model.shoulder + 22)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(
            // Gradient rim, invisible at the screen edge and strongest near the top shoulders.
            shape.stroke(LinearGradient(stops: [
                .init(color: .white.opacity(0.0), location: 0.0),
                .init(color: .white.opacity(0.22), location: 0.25),
                .init(color: .white.opacity(0.06), location: 1.0),
            ], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            .opacity(expanded ? 1 : 0)
        )
        // Shadow on its own background shape: shadowing the whole group would flatten the
        // layer-animated audio bars and force a CPU redraw of every gradient each frame.
        .background(
            shape.fill(Color.black)
                .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 8)
                .opacity(expanded || toast != nil ? 1 : 0)
        )
        .contentShape(shape)
        .onTapGesture { if !expanded { onTap() } }
    }
}

struct ExpandedContent: View {
    let topInset: CGFloat
    let services: Services
    var onSettings: () -> Void
    @ObservedObject private var settings: AppSettings
    @ObservedObject private var weather: WeatherService
    @State private var showOutputs = false

    init(topInset: CGFloat, services: Services, onSettings: @escaping () -> Void) {
        self.topInset = topInset
        self.services = services
        self.onSettings = onSettings
        _settings = ObservedObject(wrappedValue: services.settings)
        _weather = ObservedObject(wrappedValue: services.weather)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                TimelineView(.everyMinute) { context in
                    Text(context.date, format: .dateTime.weekday(.wide).month().day())
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
                if settings.showWeather, let w = weather.now {
                    HStack(spacing: 4) {
                        Image(systemName: w.symbol).symbolRenderingMode(.multicolor)
                        Text(w.text)
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .help("Weather from Open-Meteo")
                }
                Spacer()
                if settings.showOutputPicker {
                    HeaderButton(symbol: showOutputs ? "xmark" : "hifispeaker.fill", help: "Audio output") {
                        let opening = !showOutputs
                        Motion.perform(showing: opening) { showOutputs = opening }
                    }
                }
                HeaderButton(symbol: "gearshape.fill", help: "Settings", action: onSettings)
            }
            .frame(height: max(topInset, 24))

            Group {
                if showOutputs && settings.showOutputPicker {
                    OutputList(audio: services.audio)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    NowPlayingCard(player: services.player, settings: settings, lyrics: services.lyrics)
                        .transition(.opacity)
                }
            }
            .padding(.top, 8)
            .frame(maxHeight: .infinity)
        }
        .padding(.bottom, 16)
        .onAppear { weather.refreshIfStale() }
    }
}

struct HeaderButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(hovering ? 0.95 : 0.65))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.18 : 0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(BubblePressStyle())
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// CoreAudio output devices as bubble rows; tapping one makes it the default output.
struct OutputList: View {
    @ObservedObject var audio: AudioOutputs

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 6) {
                ForEach(audio.devices) { device in
                    let selected = device.id == audio.defaultID
                    Button { audio.select(device.id) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: Self.symbol(for: device.name))
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 20)
                            Text(device.name)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .lineLimit(1)
                            Spacer()
                            if selected {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 14))
                            }
                        }
                        .foregroundColor(selected ? .black : .white)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Capsule().fill(selected ? Color.white.opacity(0.92) : Color.white.opacity(0.1)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(BubblePressStyle())
                }
            }
        }
        .onAppear { audio.reload(announce: false) }
    }

    static func symbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods") { return "airpodspro" }
        if n.contains("headphone") || n.contains("beats") { return "headphones" }
        if n.contains("display") || n.contains("hdmi") || n.contains("tv") { return "tv" }
        if n.contains("macbook") || n.contains("internal") || n.contains("built-in") { return "laptopcomputer" }
        return "hifispeaker.fill"
    }
}

// MARK: Toasts

extension Toast {
    /// Same-kind toasts update in place instead of re-running the entry transition.
    var identity: String {
        switch self {
        case .battery: return "battery"
        case .lowPower: return "lowPower"
        case .bluetooth(let name, _, _): return "bt-" + name
        case .level(let kind, _, _): return kind == .volume ? "volume" : "brightness"
        case .output: return "output"
        }
    }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 12) {
            switch toast {
            case let .battery(level, charging, title):
                BatteryGlyph(level: level, charging: charging)
                label(title, detail: nil)
                Spacer()
                Text("\(level)%")
                    .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundColor(level <= 20 && !charging ? .red : .white)
            case let .lowPower(on):
                icon("bolt.circle.fill", color: on ? .yellow : .white)
                label(on ? "Low Power Mode on" : "Low Power Mode off", detail: nil)
                Spacer()
            case let .bluetooth(name, detail, connected):
                icon(OutputList.symbol(for: name) == "hifispeaker.fill" ? "dot.radiowaves.left.and.right" : OutputList.symbol(for: name),
                     color: connected ? .blue : .white.opacity(0.6))
                label(name, detail: detail)
                Spacer()
            case let .level(kind, value, muted):
                icon(Self.levelSymbol(kind: kind, value: value, muted: muted), color: .white)
                    .frame(width: 26)
                LevelBar(value: muted ? 0 : value)
                Text("\(Int((muted ? 0 : value) * 100))")
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 30, alignment: .trailing)
            case let .output(name):
                icon(OutputList.symbol(for: name), color: .white)
                label("Output", detail: name)
                Spacer()
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func icon(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(color)
    }

    private func label(_ title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
    }

    static func levelSymbol(kind: Toast.Level, value: Double, muted: Bool) -> String {
        if kind == .brightness { return value < 0.5 ? "sun.min.fill" : "sun.max.fill" }
        if muted || value == 0 { return "speaker.slash.fill" }
        if value < 0.34 { return "speaker.wave.1.fill" }
        if value < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

/// Capsule level meter that animates between values.
struct LevelBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(Color.white)
                    .frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 6)
        .animation(Motion.feedback, value: value)
    }
}

/// Battery outline whose fill sweeps up to the level; the bolt pulses while charging.
struct BatteryGlyph: View {
    let level: Int
    let charging: Bool
    @State private var shown: Double = 0
    @State private var pulse = false

    var body: some View {
        let fill: Color = charging ? .green : (level <= 20 ? .red : .white)
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .stroke(Color.white.opacity(0.55), lineWidth: 1.5)
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(fill)
                    .frame(width: max(2, 25 * shown))
                    .padding(2.5)
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 1)
                        .frame(maxWidth: .infinity)
                        .scaleEffect(pulse ? 1.15 : 0.9)
                }
            }
            .frame(width: 30, height: 15)
            RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.55)).frame(width: 2, height: 5)
        }
        .onAppear {
            Motion.perform(MotionPolicy.feedback(reduceMotion: Motion.reduced)) { shown = Double(level) / 100 }
            if charging && !Motion.reduced {
                withAnimation(.easeInOut(duration: MotionPolicy.openDuration).repeatCount(3, autoreverses: true)) { pulse = true }
            }
        }
    }
}

// MARK: Onboarding

/// First-launch tour shown inside the island.
struct OnboardingView: View {
    let topInset: CGFloat
    let onSettings: () -> Void
    let onDone: () -> Void
    @State private var page = 0

    private struct Page { let symbol: String; let title: String; let text: String }
    private let pages = [
        Page(symbol: "hand.point.up.left.fill", title: "Welcome to Hub's Island",
             text: "Point at the pill to peek. Click to open. Press Esc or click anywhere else to close."),
        Page(symbol: "waveform.circle.fill", title: "Live activities",
             text: "Music, battery, AirPods, volume and weather show up here. macOS asks for Location, Bluetooth or Automation only when a feature first needs it."),
        Page(symbol: "slider.horizontal.3", title: "Make it yours",
             text: "Turn features on or off, resize the island and hide menu bar icons in Settings."),
    ]

    var body: some View {
        let p = pages[page]
        VStack(spacing: 10) {
            Spacer().frame(height: max(topInset, 24) - 6)
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: p.symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white, .white.opacity(0.35))
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(0.12)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text(p.text)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .id(page)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            Spacer(minLength: 0)
            HStack {
                HStack(spacing: 6) {
                    ForEach(pages.indices, id: \.self) { i in
                        Capsule().fill(Color.white.opacity(i == page ? 0.9 : 0.25))
                            .frame(width: i == page ? 16 : 6, height: 6)
                    }
                }
                Spacer()
                if page == pages.count - 1 {
                    BubblePill(symbol: "gearshape.fill", title: "Settings") { onDone(); onSettings() }
                    BubblePill(symbol: "checkmark", title: "Done", action: onDone)
                } else {
                    BubblePill(symbol: "xmark", title: "Skip", action: onDone)
                    BubblePill(symbol: "arrow.right", title: "Next") {
                        Motion.perform(showing: true) { page += 1 }
                    }
                }
            }
        }
        .padding(.bottom, 16)
    }
}

/// Soft colored edge glow behind the collapsed pill while a track plays.
struct PlayingGlow: View {
    @ObservedObject var player: NowPlayingService
    @ObservedObject var settings: AppSettings
    let shape: IslandShape
    let visible: Bool

    var body: some View {
        let on = visible && settings.playingGlow && (player.info?.isPlaying ?? false)
        let color = Color(nsColor: player.accent ?? NSColor(white: 0.9, alpha: 1))
        shape
            .stroke(color.opacity(0.75), lineWidth: 2)
            .blur(radius: 3.5)
            .opacity(on ? 1 : 0)
            // Fades in over 0.18 s; turns off in the same frame (no lingering glow).
            .animation(Motion.show(on), value: on)
    }
}
