import AppKit
import Darwin

/// Local-only CPU and memory readings of this app. Nothing is sent anywhere.
final class DiagnosticsSampler: ObservableObject {
    @Published private(set) var cpuPercent: Double = 0
    @Published private(set) var memoryMB: Double = 0
    private var timer: Timer?
    private var lastCPU: Double = 0
    private var lastWall: Date = Date()

    func start() {
        guard timer == nil else { return }
        lastCPU = Self.cpuSeconds()
        lastWall = Date()
        memoryMB = Self.footprintMB()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let cpu = Self.cpuSeconds()
        let now = Date()
        let wall = now.timeIntervalSince(lastWall)
        if wall > 0 { cpuPercent = (cpu - lastCPU) / wall * 100 }
        lastCPU = cpu
        lastWall = now
        memoryMB = Self.footprintMB()
    }

    static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    /// Physical footprint, the number Activity Monitor shows as "Memory".
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    /// Plain-text report for the clipboard.
    func report(settings: AppSettings, services: Services, brightnessAvailable: Bool) -> String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let screen = ScreenLocator.target(id: settings.screenID)
        let notch = screen.flatMap(ScreenLocator.notchSize(of:)) != nil ? "real notch" : "simulated notch"
        func onOff(_ b: Bool) -> String { b ? "on" : "off" }
        return """
        Hub Island \(version) (\(build))
        macOS \(os)
        CPU: \(String(format: "%.1f", cpuPercent))%   Memory: \(String(format: "%.1f", memoryMB)) MB
        Screen: \(screen?.localizedName ?? "none") (\(notch)); setting: \(settings.screenID)
        Notch: \(Int(settings.notchWidth)) x \(settings.notchHeight == 0 ? "auto" : String(Int(settings.notchHeight))), offset \(Int(settings.notchOffset))
        Now playing: \(onOff(settings.showNowPlaying)), track loaded: \(services.player.info != nil ? "yes" : "no")
        Battery alerts: \(onOff(settings.showBatteryAlerts)); Bluetooth: \(onOff(settings.showBluetooth))
        Volume HUD: \(onOff(settings.showVolumeHUD)); Brightness HUD: \(onOff(settings.showBrightnessHUD)) (readable: \(brightnessAvailable ? "yes" : "no"))
        Output picker: \(onOff(settings.showOutputPicker)); outputs: \(services.audio.devices.count)
        Weather: \(onOff(settings.showWeather)) - \(services.weather.status)
        Lyrics: \(onOff(settings.showLyrics)) - \(services.lyrics.status)
        MediaRemote: \(onOff(settings.useMediaRemote)) (loaded: \(services.player.mediaRemoteActive ? "yes" : "no")); SkyLight lock card: \(onOff(settings.showOnLockScreen))
        Nothing here is sent anywhere.
        """
    }
}
