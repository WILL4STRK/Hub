import AppKit
import SwiftUI

/// The Island page of Hub's Settings (Awning's settings, minus launch at login and the menu-bar hider,
/// which Hub's General and Menu Bar pages own now).
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let services: Services
    let brightnessAvailable: Bool
    let lockSupported: Bool
    @ObservedObject var diagnostics: DiagnosticsSampler
    @State private var screens = ScreenLocator.choices()
    @State private var copied = false

    private var hasRealNotch: Bool {
        ScreenLocator.target(id: settings.screenID).flatMap(ScreenLocator.notchSize(of:)) != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                BubbleSection(title: "General") {
                    BubbleRow(symbol: "sparkles", color: .purple, title: "Show welcome tour again") {
                        Button("Replay") { settings.onboarded = false }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                BubbleSection(title: "Display",
                              footer: hasRealNotch ? "Size and position apply to the simulated notch; this screen has a real one." : nil) {
                    BubbleRow(symbol: "display", color: .blue, title: "Screen") {
                        Picker("", selection: $settings.screenID) {
                            Text("Automatic").tag("auto")
                            ForEach(screens) { screen in
                                Text(screen.name).tag(screen.id)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 200)
                    }
                    BubbleDivider()
                    BubbleRow(symbol: "capsule.fill", color: .indigo, title: "Simulate notch") {
                        Toggle("", isOn: $settings.simulateNotch).labelsHidden().toggleStyle(.switch)
                    }
                    BubbleDivider()
                    BubbleRow(symbol: "arrow.left.and.right", color: .teal, title: "Width") {
                        SliderValue(value: $settings.notchWidth, range: 120...360, label: "\(Int(settings.notchWidth)) pt")
                    }
                    BubbleDivider()
                    BubbleRow(symbol: "arrow.up.and.down", color: .teal, title: "Height") {
                        SliderValue(value: $settings.notchHeight, range: 0...44,
                                    label: settings.notchHeight < 20 ? "Auto" : "\(Int(settings.notchHeight)) pt")
                    }
                    BubbleDivider()
                    BubbleRow(symbol: "arrow.left.arrow.right", color: .teal, title: "Position") {
                        SliderValue(value: $settings.notchOffset, range: -600...600,
                                    label: settings.notchOffset == 0 ? "Center" : "\(Int(settings.notchOffset))")
                        Button("Reset") {
                            settings.notchWidth = 190
                            settings.notchHeight = 0
                            settings.notchOffset = 0
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                BubbleSection(title: "Now Playing",
                              footer: "Works with Spotify, Music and browser players. Spotify art shows when macOS provides it; Hub never downloads it.") {
                    BubbleRow(symbol: "music.note", color: .pink, title: "Show now playing") {
                        Toggle("", isOn: $settings.showNowPlaying).labelsHidden().toggleStyle(.switch)
                    }
                    BubbleDivider()
                    BubbleRow(symbol: "waveform", color: .orange, title: "Audio bars in pill") {
                        Toggle("", isOn: $settings.showAudioBars).labelsHidden().toggleStyle(.switch)
                    }
                    BubbleDivider()
                    BubbleRow(symbol: "sparkle", color: .purple, title: "Album-color glow") {
                        Toggle("", isOn: $settings.playingGlow).labelsHidden().toggleStyle(.switch)
                    }
                    BubbleDivider()
                    BubbleRow(symbol: "quote.bubble.fill", color: .mint, title: "Synced lyrics (LRCLIB)") {
                        Toggle("", isOn: $settings.showLyrics).labelsHidden().toggleStyle(.switch)
                    }
                    BubbleDivider()
                    BubbleRow(symbol: "play.circle.fill", color: .green, title: "Play button starts") {
                        Picker("", selection: $settings.defaultPlayer) {
                            Text("Spotify").tag("spotify")
                            Text("Music").tag("music")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                    }
                }

                BubbleSection(title: "Live Activities",
                              footer: brightnessAvailable ? "The island's notices appear alongside the system's own volume and brightness pop-ups."
                                                          : "Brightness can't be read on this Mac, so the brightness notice stays off.") {
                    Group {
                    BubbleRow(symbol: "battery.75", color: .green, title: "Battery alerts") {
                        Toggle("", isOn: $settings.showBatteryAlerts).labelsHidden().toggleStyle(.switch)
                    }
                    BubbleDivider()
                    BubbleRow(symbol: "airpodspro", color: .blue, title: "Bluetooth & AirPods") {
                        Toggle("", isOn: $settings.showBluetooth).labelsHidden().toggleStyle(.switch)
                    }
                    BubbleDivider()
                    BubbleRow(symbol: "speaker.wave.2.fill", color: .gray, title: "Volume notice") {
                        Toggle("", isOn: $settings.showVolumeHUD).labelsHidden().toggleStyle(.switch)
                    }
                    }
                    BubbleDivider()
                    Group {
                    BubbleRow(symbol: "sun.max.fill", color: .yellow, title: "Brightness notice") {
                        Toggle("", isOn: $settings.showBrightnessHUD).labelsHidden().toggleStyle(.switch)
                            .disabled(!brightnessAvailable)
                    }
                    BubbleDivider()
                    BubbleRow(symbol: "hifispeaker.fill", color: .gray, title: "Audio output picker") {
                        Toggle("", isOn: $settings.showOutputPicker).labelsHidden().toggleStyle(.switch)
                    }
                    BubbleDivider()
                    BubbleRow(symbol: "cloud.sun.fill", color: .cyan, title: "Weather (Open-Meteo)") {
                        Toggle("", isOn: $settings.showWeather).labelsHidden().toggleStyle(.switch)
                    }
                    }
                }

                BubbleSection(title: "Private APIs",
                              footer: "Both are undocumented macOS frameworks and may stop working after a macOS update. Off, or if one fails to load: now playing uses AppleScript for Spotify and Music only, and the lock-screen card is skipped.") {
                    BubbleRow(symbol: "music.note.list", color: .pink, title: "MediaRemote: now playing for every app") {
                        Text(settings.useMediaRemote ? (services.player.mediaRemoteActive ? "Loaded" : "Failed, using AppleScript") : "AppleScript")
                            .font(.system(size: 11, design: .rounded)).foregroundColor(.secondary)
                        Toggle("", isOn: $settings.useMediaRemote).labelsHidden().toggleStyle(.switch)
                    }
                    BubbleDivider()
                    BubbleRow(symbol: "lock.fill", color: .black, title: "SkyLight: card on the lock screen") {
                        Text(lockSupported ? "Available" : "Not found")
                            .font(.system(size: 11, design: .rounded)).foregroundColor(.secondary)
                        Toggle("", isOn: $settings.showOnLockScreen).labelsHidden().toggleStyle(.switch)
                            .disabled(!lockSupported)
                    }
                }

                BubbleSection(title: "Lock Screen",
                              footer: lockSupported
                                ? "Experimental. Uses an undocumented macOS API, so it may stop working after a macOS update. It never takes keyboard focus, so your password field keeps working, and it can't unlock anything. Switch it on under Private APIs. If it misbehaves, turn it off there or quit Hub; everything it adds is removed when Hub quits."
                                : "Not available: the system API it needs was not found on this macOS version.") {
                    BubbleRow(symbol: "rectangle.bottomthird.inset.filled", color: .black, title: "Card position") {
                        Picker("", selection: $settings.lockCardPosition) {
                            Text("Below login").tag("bottom")
                            Text("Top").tag("top")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 170)
                        .disabled(!settings.showOnLockScreen)
                    }
                    BubbleDivider()
                    BubbleRow(symbol: "arrow.up.and.down", color: .black, title: "Height from bottom") {
                        SliderValue(value: $settings.lockCardHeight, range: 0...900,
                                    label: "\(Int(settings.lockCardHeight)) pt")
                            .disabled(!settings.showOnLockScreen || settings.lockCardPosition != "bottom")
                    }
                }

                BubbleSection(title: "Diagnostics", footer: "Measured on this Mac only. Nothing is sent anywhere.") {
                    BubbleRow(symbol: "cpu", color: .red, title: "CPU") {
                        Text(String(format: "%.1f %%", diagnostics.cpuPercent))
                            .font(.system(size: 13, design: .rounded).monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    BubbleDivider()
                    BubbleRow(symbol: "memorychip", color: .red, title: "Memory") {
                        Text(String(format: "%.1f MB", diagnostics.memoryMB))
                            .font(.system(size: 13, design: .rounded).monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    BubbleDivider()
                    BubbleRow(symbol: "doc.on.clipboard", color: .gray, title: "Diagnostics report") {
                        Button(copied ? "Copied" : "Copy") {
                            let text = diagnostics.report(settings: settings, services: services,
                                                          brightnessAvailable: brightnessAvailable)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = ScreenLocator.choices()
        }
    }
}

/// Compact slider with a value label.
struct SliderValue: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Slider(value: $value, in: range, step: 1)
                .frame(width: 140)
            Text(label)
                .font(.system(size: 12, design: .rounded).monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }
}

// MARK: iOS-style grouped bubbles

struct BubbleSection<Content: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.leading, 14)
            VStack(spacing: 0) { content }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                )
            if let footer, !footer.isEmpty {
                Text(footer)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct BubbleRow<Accessory: View>: View {
    let symbol: String
    let color: Color
    let title: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color.gradient)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                )
            Text(title).font(.system(size: 13, design: .rounded))
            Spacer(minLength: 8)
            accessory
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 46)
    }
}

struct BubbleDivider: View {
    var body: some View {
        Divider().padding(.leading, 52)
    }
}
